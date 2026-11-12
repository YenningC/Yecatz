"""One-use, encrypted LAN file transfer shared with the macOS version."""
import base64
import hashlib
import json
import os
import secrets
import socket
import struct
import threading
import time
import uuid
from pathlib import Path

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from PySide6.QtCore import QObject, Signal

MAX_FRAME = 131072
MAX_FILE = 1073741824
DISCOVERY_PORT = 47857


def short_secret(code):
    return hashlib.sha256(b"yecatz-short-v2:" + code.encode("ascii")).digest()


def discovery_digest(nonce, code):
    return hashlib.sha256(b"yecatz-discovery-v2:" + nonce + code.encode("ascii")).digest()


def find_short_code(code):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.settimeout(1)
        nonce = os.urandom(16)
        query = b"YZD2" + nonce + discovery_digest(nonce, code)
        for _ in range(5):
            sock.sendto(query, ("255.255.255.255", DISCOVERY_PORT))
            try:
                reply, source = sock.recvfrom(128)
                if len(reply) == 22 and reply[:4] == b"YZR2" and reply[4:20] == nonce:
                    port = struct.unpack(">H", reply[20:])[0]
                    if port:
                        return source[0], port, short_secret(code)
            except socket.timeout:
                continue
    raise OSError("device not found")


def encode_code(host, port, secret):
    raw = bytes([1]) + socket.inet_aton(host) + struct.pack(">H", port) + secret
    if len(raw) != 23:
        raise ValueError("invalid invitation")
    return "YZ1-" + base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def decode_code(code):
    code = code.strip()
    if len(code) == 8 and code.isascii() and code.isdigit():
        return None, None, short_secret(code)
    if not code.startswith("YZ1-"):
        raise ValueError("连接码不正确。")
    try:
        raw = base64.b64decode(code[4:] + "=" * (-len(code[4:]) % 4), altchars=b"-_", validate=True)
        if len(raw) != 23 or raw[0] != 1 or raw[1] == 0 or raw[1] >= 224:
            raise ValueError()
        port = struct.unpack(">H", raw[5:7])[0]
        if not port:
            raise ValueError()
        return socket.inet_ntoa(raw[1:5]), port, raw[7:23]
    except (ValueError, UnicodeError):
        raise ValueError("连接码不正确。") from None


class Cipher:
    def __init__(self, secret, session_nonce, initiator):
        def derive(label):
            return HKDF(algorithm=hashes.SHA256(), length=32,
                        salt=b"yecatz-lan-v1" + session_nonce, info=label).derive(secret)
        self.send_label = b"client" if initiator else b"host"
        self.recv_label = b"host" if initiator else b"client"
        self.send_cipher = ChaCha20Poly1305(derive(self.send_label))
        self.recv_cipher = ChaCha20Poly1305(derive(self.recv_label))
        self.sent = 0
        self.received = 0

    def seal(self, value):
        nonce = b"\0" * 4 + struct.pack(">Q", self.sent)
        result = self.send_cipher.encrypt(nonce, value, self.send_label)
        self.sent += 1
        return result

    def open(self, value):
        nonce = b"\0" * 4 + struct.pack(">Q", self.received)
        result = self.recv_cipher.decrypt(nonce, value, self.recv_label)
        self.received += 1
        return result


def receive_exact(sock, size):
    output = bytearray()
    while len(output) < size:
        part = sock.recv(size - len(output))
        if not part:
            raise ConnectionError("connection closed")
        output.extend(part)
    return bytes(output)


def local_ipv4():
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # This only asks the OS which interface it would use; no packet is sent.
        try:
            probe.connect(("1.1.1.1", 53))
            address = probe.getsockname()[0]
            if address and not address.startswith(("127.", "169.254.")):
                return address
        except OSError:
            pass
    finally:
        probe.close()
    for result in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET, socket.SOCK_STREAM):
        address = result[4][0]
        if address and not address.startswith(("127.", "169.254.", "0.")):
            return address
    raise OSError("no local address")


class Transfer(QObject):
    state_changed = Signal(str)
    notice = Signal(str)
    code_ready = Signal(str)
    pair_requested = Signal(str)
    file_offered = Signal(str, int)

    def __init__(self):
        super().__init__()
        self.state = "idle"
        self.listener = None
        self.discovery = None
        self.sock = None
        self.cipher = None
        self.generation = 0
        self.send_lock = threading.Lock()
        self.choice = threading.Event()
        self.choice_value = None
        self.sending = None
        self.offer_pending = False
        self.receiving = None
        self.temporary = None
        self.destination = None
        self.expected = 0
        self.received = 0
        self.hasher = None
        self.closed = threading.Event()

    def set_state(self, state):
        self.state = state
        self.state_changed.emit(state)

    def disconnect(self):
        self.generation += 1
        self.closed.set()
        self.choice.set()
        for sock in (self.sock, self.listener, self.discovery):
            if sock is not None:
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                try:
                    sock.close()
                except OSError:
                    pass
        self.sock = None
        self.listener = None
        self.discovery = None
        self.cipher = None
        self.sending = None
        self.offer_pending = False
        self.cleanup_receiver()
        self.set_state("idle")

    def cleanup_receiver(self):
        if self.receiving:
            self.receiving.close()
        self.receiving = None
        if self.temporary:
            try:
                self.temporary.unlink(missing_ok=True)
            except OSError:
                pass
        self.temporary = None
        self.destination = None

    def start_host(self):
        self.disconnect()
        self.closed = threading.Event()
        token = self.generation
        self.set_state("waiting")
        threading.Thread(target=self.host_thread, args=(token,), daemon=True).start()

    def host_thread(self, token):
        try:
            ip = local_ipv4()
            code = f"{secrets.randbelow(100_000_000):08d}"
            secret = short_secret(code)
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            listener.bind((ip, 0))
            listener.listen(1)
            listener.settimeout(300)
            if self.generation != token:
                listener.close()
                return
            self.listener = listener
            discovery = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            discovery.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            discovery.bind(("", DISCOVERY_PORT))
            discovery.settimeout(1)
            if self.generation != token:
                discovery.close()
                return
            self.discovery = discovery
            threading.Thread(target=self.discovery_thread, args=(token, discovery, code, listener.getsockname()[1]), daemon=True).start()
            self.code_ready.emit(code)
            conn, _ = listener.accept()
            if self.generation != token:
                conn.close()
                return
            self.sock = conn
            conn.settimeout(30)
            self.set_state("connecting")
            header = receive_exact(conn, 19)
            if header[:3] != b"YH1":
                raise ValueError("bad header")
            self.cipher = Cipher(secret, header[3:], initiator=False)
            message = self.receive_message()
            if message.get("type") != "hello" or not isinstance(message.get("name"), str) or len(message["name"]) > 100:
                raise ValueError("bad hello")
            self.choice.clear()
            self.pair_requested.emit(message["name"])
            if not self.choice.wait(30) or self.closed.is_set() or not self.choice_value:
                self.send_message({"type": "pairRejected"})
                return
            self.send_message({"type": "paired"})
            listener.close()
            self.listener = None
            discovery.close()
            self.discovery = None
            self.run_connected(token)
        except Exception:
            if self.generation == token:
                self.notice.emit("连接失败，请检查同网权限并重新配对。")
        finally:
            if self.generation == token:
                self.disconnect()

    def connect_code(self, code):
        address, port, secret = decode_code(code)
        self.disconnect()
        self.closed = threading.Event()
        token = self.generation
        self.set_state("connecting")
        threading.Thread(target=self.client_thread, args=(token, address, port, secret, code.strip()), daemon=True).start()

    def discovery_thread(self, token, sock, code, tcp_port):
        while self.generation == token:
            try:
                query, source = sock.recvfrom(128)
                if (len(query) == 52 and query[:4] == b"YZD2"
                        and secrets.compare_digest(query[20:], discovery_digest(query[4:20], code))):
                    sock.sendto(b"YZR2" + query[4:20] + struct.pack(">H", tcp_port), source)
            except socket.timeout:
                continue
            except OSError:
                break

    def client_thread(self, token, address, port, secret, code):
        try:
            if address is None:
                address, port, secret = find_short_code(code)
                if self.generation != token:
                    return
            conn = socket.create_connection((address, port), timeout=30)
            if self.generation != token:
                conn.close()
                return
            self.sock = conn
            nonce = os.urandom(16)
            self.cipher = Cipher(secret, nonce, initiator=True)
            conn.sendall(b"YH1" + nonce)
            self.send_message({"type": "hello", "name": socket.gethostname()[:100]})
            reply = self.receive_message()
            if reply.get("type") != "paired":
                self.notice.emit("对方没有接受连接。")
                return
            self.run_connected(token)
        except Exception:
            if self.generation == token:
                self.notice.emit("连接失败，请检查同网权限和连接码。")
        finally:
            if self.generation == token:
                self.disconnect()

    def decide(self, value):
        self.choice_value = value
        self.choice.set()

    def send_message(self, value):
        with self.send_lock:
            if self.sock is None or self.cipher is None:
                raise ConnectionError("not connected")
            payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            encrypted = self.cipher.seal(payload)
            if len(encrypted) > MAX_FRAME:
                raise ValueError("message too large")
            self.sock.sendall(struct.pack(">I", len(encrypted)) + encrypted)

    def receive_message(self):
        size = struct.unpack(">I", receive_exact(self.sock, 4))[0]
        if not 16 <= size <= MAX_FRAME:
            raise ValueError("bad frame")
        return json.loads(self.cipher.open(receive_exact(self.sock, size)).decode("utf-8"))

    def send_file(self, path):
        if self.state != "connected" or self.sending or self.receiving or self.offer_pending:
            self.notice.emit("正在传输，请稍等。")
            return
        try:
            source = Path(path)
            size = source.stat().st_size
            if not source.is_file() or size > MAX_FILE or len(source.name.encode("utf-8")) > 255:
                raise ValueError()
            self.sending = source
            token = self.generation
            threading.Thread(target=self.offer_file, args=(token, source.name, size), daemon=True).start()
        except (OSError, ValueError, ConnectionError):
            self.sending = None
            self.notice.emit("请选择不超过 1 GB 的单个文件。")

    def offer_file(self, token, name, size):
        try:
            self.send_message({"type": "offer", "name": name, "size": size})
            self.notice.emit("等待对方接收…")
        except (OSError, ValueError, ConnectionError):
            if self.generation == token:
                self.notice.emit("发送失败，连接已断开。")
                self.disconnect()

    def run_connected(self, token):
        self.sock.settimeout(None)
        self.set_state("connected")
        self.notice.emit("已连接，把文件放进纸箱。")
        while self.generation == token:
            message = self.receive_message()
            kind = message.get("type")
            if kind == "offer":
                name, size = message.get("name"), message.get("size")
                if (not isinstance(name, str) or not name
                        or name in (".", "..") or "/" in name or "\\" in name
                        or any(ord(character) < 32 or ord(character) == 127 for character in name)
                        or len(name.encode("utf-8")) > 255 or type(size) is not int or not 0 <= size <= MAX_FILE):
                    raise ValueError("invalid offer")
                if self.sending or self.receiving or self.offer_pending:
                    self.send_message({"type": "reject"})
                    continue
                self.offer_pending = True
                self.choice.clear()
                self.file_offered.emit(name, size)
                accepted = self.choice.wait(300) and not self.closed.is_set() and self.choice_value
                self.offer_pending = False
                if not accepted:
                    self.send_message({"type": "reject"})
                    continue
                destination = Path(self.choice_value)
                if destination.exists():
                    self.send_message({"type": "reject"})
                    self.notice.emit("目标文件已存在，请选择其他名称。")
                    continue
                try:
                    temporary = destination.parent / (".yecatz-" + uuid.uuid4().hex + ".part")
                    self.receiving = temporary.open("xb")
                    self.temporary = temporary
                    self.destination = destination
                    self.expected, self.received, self.hasher = size, 0, hashlib.sha256()
                    self.send_message({"type": "accept"})
                    self.notice.emit("正在接收文件…")
                except OSError:
                    self.cleanup_receiver()
                    self.send_message({"type": "reject"})
                    self.notice.emit("无法保存文件。")
            elif kind == "accept" and self.sending:
                self.notice.emit("正在发送文件…")
                checksum = hashlib.sha256()
                with self.sending.open("rb") as source:
                    while True:
                        chunk = source.read(32768)
                        if not chunk:
                            break
                        checksum.update(chunk)
                        self.send_message({"type": "chunk", "data": base64.b64encode(chunk).decode("ascii")})
                self.send_message({"type": "done", "digest": checksum.hexdigest()})
            elif kind == "reject" and self.sending:
                self.sending = None
                self.notice.emit("对方没有接收文件。")
            elif kind == "chunk" and self.receiving:
                encoded = message.get("data")
                if not isinstance(encoded, str) or len(encoded) > 43692:
                    raise ValueError("invalid chunk")
                chunk = base64.b64decode(encoded, validate=True)
                if not chunk or len(chunk) > 32768 or self.received + len(chunk) > self.expected:
                    raise ValueError("invalid chunk")
                self.receiving.write(chunk)
                self.hasher.update(chunk)
                self.received += len(chunk)
            elif kind == "done" and self.receiving:
                if self.received != self.expected or message.get("digest") != self.hasher.hexdigest():
                    raise ValueError("digest mismatch")
                self.receiving.close()
                self.receiving = None
                if os.name == "nt":
                    os.rename(self.temporary, self.destination)
                else:
                    os.link(self.temporary, self.destination)
                    self.temporary.unlink()
                self.temporary = None
                self.destination = None
                self.send_message({"type": "complete"})
                self.notice.emit("文件已接收。")
            elif kind == "complete" and self.sending:
                self.sending = None
                self.notice.emit("文件已送达。")
            else:
                raise ValueError("unexpected message")

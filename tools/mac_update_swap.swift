import Darwin

guard CommandLine.arguments.count == 3 else { exit(2) }
let installed = CommandLine.arguments[1]
let staged = CommandLine.arguments[2]

// Exchange both names in one operation. An unsupported volume leaves both paths intact.
guard renameatx_np(AT_FDCWD, installed, AT_FDCWD, staged, UInt32(RENAME_SWAP)) == 0 else {
    perror("Yecatz bundle exchange")
    exit(1)
}

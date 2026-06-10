# zig-pesel

Simple CLI for:

- generating random valid PESEL numbers into a file
- working with AVL, red-black, and 2-3-4 trees in an interactive session

## Build

```sh
zig build
```

## Run

Interactive mode:

```sh
zig build run
```

Direct PESEL generation:

```sh
zig build run -- generate 1000 pesel.txt
```

## Main Commands

From the main prompt:

- `help`
- `generate [count file]`
- `tree [new <avl|rb|234> [keys-file] | load <file>]`
- `quit`

If you run `generate` without arguments, the program asks for the count and output file.

## Tree Session

Create a new tree:

```text
tree new avl
tree new rb
tree new 234
tree new avl keys.txt
```

Load a saved tree:

```text
tree load mytree.bin
```

Import newline-separated keys into the current tree:

```text
import keys.txt
```

`keys.txt` should contain one unsigned integer per line. Both Unix (`\n`) and Windows (`\r\n`) line endings are supported.

Tree session commands:

- `help`
- `insert <key>`
- `remove <key>`
- `contains <key>`
- `import <file>`
- `print`
- `explore`
- `stats`
- `save <file>`
- `load <file>`
- `back`
- `quit`

## Notes

- PESEL generation only writes the file if the target file does not already exist.
- Tree save/load keeps the tree type and structure in a binary format.
- `tree load <file>` loads the binary tree save format. Text key files should be imported with `tree new <type> <file>` or `import <file>`.

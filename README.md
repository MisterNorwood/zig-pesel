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
- `tree [new <avl|rb|234> | load <file>]`
- `quit`

If you run `generate` without arguments, the program asks for the count and output file.

## Tree Session

Create a new tree:

```text
tree new avl
tree new rb
tree new 234
```

Load a saved tree:

```text
tree load mytree.bin
```

Tree session commands:

- `help`
- `insert <key>`
- `remove <key>`
- `contains <key>`
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

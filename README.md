# zig-pesel

English and Polish documentation for building and running the CLI.

## English

### Overview

`zig-pesel` is a command-line application written in Zig. It exposes two user-facing features:

- generating files with random valid PESEL numbers
- working interactively with three search tree implementations: AVL, red-black, and 2-3-4

The CLI is the supported interface described in this document. Internal code that is not reachable from the CLI is intentionally omitted here.

### Requirements

- Zig `0.16.0` or newer
- a terminal on Linux, macOS, or another environment supported by Zig
- enough disk space for generated output files

This project uses only Zig's standard library. No third-party dependencies are required.

### Build

From the project root:

```sh
zig build
```

This compiles the project and installs the executable to:

```text
zig-out/bin/zig_pesel
```

### Run

Start the interactive CLI:

```sh
zig build run
```

Run the already built binary directly:

```sh
./zig-out/bin/zig_pesel
```

Generate PESEL numbers without entering interactive mode:

```sh
zig build run -- generate 1000 pesel.txt
```

Equivalent direct execution:

```sh
./zig-out/bin/zig_pesel generate 1000 pesel.txt
```

### Main CLI modes

The application has two practical modes:

1. Interactive main prompt
2. Direct subcommand execution through command-line arguments

When started without arguments, the program opens the main prompt:

```text
Commands:
  help
  generate [count file]
  tree [new <avl|rb|234> [keys-file] | load <file>]
  quit
main>
```

### Main commands

- `help`: print the list of available top-level commands
- `generate [count file]`: generate valid PESEL numbers into a file
- `tree [new <avl|rb|234> [keys-file] | load <file>]`: open a tree session
- `quit`: exit the program

### PESEL generation

#### Direct usage

```sh
./zig-out/bin/zig_pesel generate 1000 pesel.txt
```

This creates `1000` valid random PESEL numbers and writes them to `pesel.txt`.

#### Interactive usage

At the `main>` prompt:

```text
generate
```

If no arguments are provided, the program asks for:

- the number of PESEL values to generate
- the output file path

Default values:

- default count: `400000000`
- default file name: `pesel.txt`

Be careful with the default count. It is intentionally very large and may create a multi-gigabyte file.

#### Output format

The generated file contains:

- one PESEL per line
- 11 digits per PESEL
- newline-separated text output

#### Important behavior

- the generator does not overwrite an existing target file
- if the target file already exists, generation is skipped

Example message:

```text
'pesel.txt' already exists. Generation skipped.
```

### Tree mode

Tree mode opens an interactive session for one of the supported tree types:

- `avl`
- `rb`
- `234`

Accepted aliases:

- `rb`, `red-black`, `redblack`
- `234`, `2-3-4`

#### Start a new tree

```sh
./zig-out/bin/zig_pesel tree new avl
./zig-out/bin/zig_pesel tree new rb
./zig-out/bin/zig_pesel tree new 234
```

Create a new tree and import keys from a text file immediately:

```sh
./zig-out/bin/zig_pesel tree new avl keys.txt
```

#### Load a saved binary tree

```sh
./zig-out/bin/zig_pesel tree load mytree.bin
```

You can also enter tree mode from the main prompt:

```text
tree new avl
tree load mytree.bin
```

If you run `tree` with no extra arguments, the program asks interactively whether to create a new tree or load an existing one.

### Tree session commands

Inside a tree session, the prompt looks like:

```text
tree[avl]>
```

Available commands:

- `help`: print tree-session help
- `insert <key>`: insert one unsigned integer key
- `remove <key>`: remove a key if it exists
- `contains <key>`: print `true` or `false`
- `import <file>`: import newline-separated keys from a text file
- `print`: print the tree in an indented textual form
- `explore`: same visible behavior as `print`
- `stats`: print tree type and current node count
- `save <file>`: save the current tree to a binary file
- `load <file>`: replace the current tree with a saved binary tree
- `back`: leave tree mode and return to `main>`
- `quit`: terminate the whole program immediately

Example session:

```text
tree new avl
insert 10
insert 5
contains 10
stats
save sample.bin
back
quit
```

### Importing keys from text files

Key import is available in two ways:

- when creating a new tree: `tree new <type> <keys-file>`
- from inside a tree session: `import <file>`

Expected file format:

- one unsigned integer per line
- blank lines are allowed and ignored
- both Unix (`\n`) and Windows (`\r\n`) line endings are supported

Example `keys.txt`:

```text
10
20
30
40
```

Import result reporting includes:

- how many keys were inserted
- how many duplicates were skipped
- how many blank lines were ignored

If a line is invalid, the CLI reports the line number and rejects the import.

### Saving and loading tree files

`save <file>` writes the current tree to a binary format that preserves:

- the tree kind
- the tree structure
- stored keys

`load <file>` expects that binary save format.

Important distinction:

- use `load` only for files previously created with `save`
- use `import` for plain text key lists

### Testing

Run tests with:

```sh
zig build test
```
## Polski

### Opis projektu

`zig-pesel` to aplikacja CLI napisana w Zig. Udostępnia dwie funkcje użytkowe:

- generowanie plików z losowymi poprawnymi numerami PESEL
- interaktywną pracę na trzech implementacjach drzew wyszukiwania: AVL, czerwono-czarnym i 2-3-4

Ta dokumentacja opisuje wyłącznie interfejs dostępny z poziomu CLI. Wewnętrzny kod, którego nie da się uruchomić z konsoli programu, został celowo pominięty.

### Wymagania

- Zig `0.16.0` lub nowszy
- terminal w systemie Linux, macOS albo innym środowisku wspieranym przez Zig
- wystarczająca ilość miejsca na dysku na pliki wyjściowe

Projekt korzysta wyłącznie ze standardowej biblioteki Zig. Nie wymaga zewnętrznych zależności.

### Kompilacja

W katalogu głównym projektu uruchom:

```sh
zig build
```

Polecenie kompiluje projekt i zapisuje binarkę w:

```text
zig-out/bin/zig_pesel
```

### Uruchamianie

Start interaktywnego CLI:

```sh
zig build run
```

Uruchomienie już zbudowanej binarki:

```sh
./zig-out/bin/zig_pesel
```

Bezpośrednie generowanie numerów PESEL bez wchodzenia do trybu interaktywnego:

```sh
zig build run -- generate 1000 pesel.txt
```

Równoważne wywołanie binarki:

```sh
./zig-out/bin/zig_pesel generate 1000 pesel.txt
```

### Główne tryby pracy CLI

Aplikacja ma dwa praktyczne tryby pracy:

1. Interaktywny prompt główny
2. Bezpośrednie uruchomienie podkomendy przez argumenty wiersza poleceń

Po uruchomieniu bez argumentów program otwiera prompt:

```text
Commands:
  help
  generate [count file]
  tree [new <avl|rb|234> [keys-file] | load <file>]
  quit
main>
```

### Komendy główne

- `help`: wypisuje listę dostępnych komend najwyższego poziomu
- `generate [count file]`: generuje poprawne numery PESEL do pliku
- `tree [new <avl|rb|234> [keys-file] | load <file>]`: otwiera sesję pracy z drzewem
- `quit`: kończy program

### Generowanie numerów PESEL

#### Użycie bezpośrednie

```sh
./zig-out/bin/zig_pesel generate 1000 pesel.txt
```

Polecenie tworzy `1000` poprawnych losowych numerów PESEL i zapisuje je do `pesel.txt`.

#### Użycie interaktywne

W promptcie `main>` wpisz:

```text
generate
```

Jeżeli nie podasz argumentów, program zapyta o:

- liczbę numerów PESEL do wygenerowania
- ścieżkę pliku wyjściowego

Wartości domyślne:

- domyślna liczba: `400000000`
- domyślna nazwa pliku: `pesel.txt`

Uwaga na domyślną liczbę. Jest bardzo duża i może wygenerować plik o rozmiarze wielu gigabajtów.

#### Format wyjścia

Wygenerowany plik zawiera:

- jeden numer PESEL w każdej linii
- 11 cyfr na każdy PESEL
- tekst rozdzielony znakami nowej linii

#### Ważne zachowanie

- generator nie nadpisuje istniejącego pliku docelowego
- jeśli plik już istnieje, generowanie zostanie pominięte

Przykładowy komunikat:

```text
'pesel.txt' already exists. Generation skipped.
```

### Tryb pracy z drzewami

Tryb drzew uruchamia interaktywną sesję dla jednego z obsługiwanych typów:

- `avl`
- `rb`
- `234`

Akceptowane aliasy:

- `rb`, `red-black`, `redblack`
- `234`, `2-3-4`

#### Utworzenie nowego drzewa

```sh
./zig-out/bin/zig_pesel tree new avl
./zig-out/bin/zig_pesel tree new rb
./zig-out/bin/zig_pesel tree new 234
```

Utworzenie nowego drzewa z natychmiastowym importem kluczy z pliku tekstowego:

```sh
./zig-out/bin/zig_pesel tree new avl keys.txt
```

#### Wczytanie zapisanego drzewa binarnego

```sh
./zig-out/bin/zig_pesel tree load mytree.bin
```

Do trybu drzewa możesz też wejść z głównego promptu:

```text
tree new avl
tree load mytree.bin
```

Jeżeli uruchomisz samo `tree`, program interaktywnie zapyta, czy utworzyć nowe drzewo, czy wczytać istniejące.

### Komendy w sesji drzewa

Wewnątrz sesji prompt wygląda tak:

```text
tree[avl]>
```

Dostępne komendy:

- `help`: wypisuje pomoc dla sesji drzewa
- `insert <key>`: wstawia jeden nieujemny klucz całkowity
- `remove <key>`: usuwa klucz, jeśli istnieje
- `contains <key>`: wypisuje `true` albo `false`
- `import <file>`: importuje klucze rozdzielone nowymi liniami z pliku tekstowego
- `print`: wypisuje drzewo w tekstowej postaci z wcięciami
- `explore`: daje taki sam widoczny efekt jak `print`
- `stats`: wypisuje typ drzewa i aktualną liczbę węzłów
- `save <file>`: zapisuje bieżące drzewo do pliku binarnego
- `load <file>`: zastępuje bieżące drzewo zapisanym drzewem binarnym
- `back`: opuszcza tryb drzewa i wraca do `main>`
- `quit`: natychmiast kończy cały program

Przykładowa sesja:

```text
tree new avl
insert 10
insert 5
contains 10
stats
save sample.bin
back
quit
```

### Import kluczy z plików tekstowych

Import kluczy jest dostępny na dwa sposoby:

- przy tworzeniu nowego drzewa: `tree new <type> <keys-file>`
- z wnętrza sesji drzewa: `import <file>`

Oczekiwany format pliku:

- jedna nieujemna liczba całkowita na linię
- puste linie są dozwolone i ignorowane
- obsługiwane są końce linii Unix (`\n`) i Windows (`\r\n`)

Przykładowy `keys.txt`:

```text
10
20
30
40
```

Raport z importu zawiera:

- liczbę wstawionych kluczy
- liczbę pominiętych duplikatów
- liczbę zignorowanych pustych linii

Jeżeli któraś linia jest niepoprawna, CLI poda numer linii i odrzuci import.

### Zapisywanie i wczytywanie plików drzewa

`save <file>` zapisuje bieżące drzewo do formatu binarnego, który zachowuje:

- typ drzewa
- strukturę drzewa
- zapisane klucze

`load <file>` oczekuje właśnie tego binarnego formatu zapisu.

Ważne rozróżnienie:

- `load` używaj tylko do plików utworzonych wcześniej przez `save`
- `import` używaj do zwykłych tekstowych list kluczy

### Testy

Aby uruchomić testy:

```sh
zig build test
```


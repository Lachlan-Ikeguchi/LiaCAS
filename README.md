# LiaCAS is a Computer Algebra System

## Usage
### stdin-stdout
Will follow the steps:
1. Read from stdin:
    - The input is structured with a header and prompt, separated by the string: `===== END HEADER =====`.
    - The header provides context to the prompt.
    - Able to pull files with `include /path/to/file/*.liaheader` that will load the definitions in the file.
2. Processing:
    - Using the definitions in the header, evaluate what the new information provided by the prompt would mean
3. Print to stdout:
    - Return the definitions.

### Interactive
Uses the command line switch `-i`: 'interactive'.  A REPL.

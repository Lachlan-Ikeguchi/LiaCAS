# LiaCAS
<u>**L**</u>iaCAS <u>**I**</u>s <u>**A**</u> <u>**C**</u>omputer <u>**A**</u>lgebra <u>**S**</u>ystem

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
    - Return the newly found equations and it's working and the new combined definitions separated by `===== NEW HEADER =====`.

### Interactive
Uses the command line switch `-i`: 'interactive'.  A REPL.

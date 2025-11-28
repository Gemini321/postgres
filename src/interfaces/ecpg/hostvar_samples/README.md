# ECPG Host Variable Samples

This mini test framework exercises the upcoming “implicit host variable” feature.
Samples are grouped by the kinds of C declarations they contain:

1. **declarations/** – only plain declarations such as `int a;`, `char name[32];`, pointer/array/struct declarations with no initializers.
2. **definitions/** – declarations that include initializers (e.g., `int a = 0;`). Only built-in types are used here.
3. **typedefs/** – files that rely on user-defined types (typedefs, structs, unions) and initialize instances of those types.

Every `.pgc` file:
- Includes `EXEC SQL INCLUDE sqlca;`.
- Connects via `EXEC SQL CONNECT sys IDENTIFIED BY 123456;`.
- Executes at least one SQL statement that uses the highlighted host variable form.
- Keeps the C code as small as possible so that each file focuses on a single syntax shape.

## Running the samples

Use `run_samples.sh` to compile each sample with `ecpg` and `cc`. The script expects a working PostgreSQL installation on PATH and will leave generated binaries next to each sample.

```bash
cd postgres/src/interfaces/ecpg/hostvar_samples
./run_samples.sh
```

You can also run a single file by invoking the script with the `.pgc` path.

```bash
./run_samples.sh declarations/scalar_int.pgc
```

Each sample connects as `sys/123456`, so adjust the SQL user/password in the source files if needed before running against your database.

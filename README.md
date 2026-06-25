# Synthesis Command Usage

This README describes how to run the parameterized Design Compiler synthesis flow.

The synthesis flow uses one shared Tcl script. You only need to specify the top module name, RTL source files, and optional output prefix from the Makefile command.

---

## Basic Command

```bash
make synthesize SYN_TOP=<top_module> SYN_SRC="<rtl_files>" SYN_OUT=<output_prefix>
```

### Arguments

| Argument | Required | Description |
|---|---:|---|
| `SYN_TOP` | Yes | Top module name to elaborate and synthesize. |
| `SYN_SRC` | Usually yes | RTL source file or source file list. |
| `SYN_OUT` | No | Output file prefix. If not specified, it defaults to `SYN_TOP`. |

---

## Important Path Rule

The Makefile runs Design Compiler inside the `build/` directory.

Pass RTL paths relative to the project root, such as `src/...`. The Tcl script will automatically resolve them from inside `build/`.

Correct:

```bash
make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv
```

Also accepted:

```bash
make synthesize SYN_TOP=PE SYN_SRC=../src/PE_array/PE.sv
```

---

## Example Commands

### Synthesize `PE`

```bash
make synthesize_PE
```

Equivalent generic command:

```bash
make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv SYN_OUT=PE
```

This generates:

```text
syn/PE_timing_max_50_rpt.txt
syn/PE_timing_min_50_rpt.txt
syn/PE_timing_max_no_rst_rpt.txt
syn/PE_area_rpt.txt
syn/PE_power_rpt.txt
syn/PE_syn.v
syn/PE_syn.sdf
syn/PE_syn.sdc
```

---

### Synthesize `PE_ori`

```bash
make synthesize_PE_ori
```

Equivalent generic command:

```bash
make synthesize SYN_TOP=PE_ori SYN_SRC=src/PE_array/PE_origin.sv SYN_OUT=PE_ori
```

This generates:

```text
syn/PE_ori_timing_max_50_rpt.txt
syn/PE_ori_timing_min_50_rpt.txt
syn/PE_ori_timing_max_no_rst_rpt.txt
syn/PE_ori_area_rpt.txt
syn/PE_ori_power_rpt.txt
syn/PE_ori_syn.v
syn/PE_ori_syn.sdf
syn/PE_ori_syn.sdc
```

---

### Synthesize `PE_LEE`

```bash
make synthesize_PE_LEE
```

Equivalent generic command:

```bash
make synthesize SYN_TOP=PE_LEE SYN_SRC=src/PE_array/PE_LEE.sv SYN_OUT=PE_LEE
```

This generates:

```text
syn/PE_LEE_timing_max_50_rpt.txt
syn/PE_LEE_timing_min_50_rpt.txt
syn/PE_LEE_timing_max_no_rst_rpt.txt
syn/PE_LEE_area_rpt.txt
syn/PE_LEE_power_rpt.txt
syn/PE_LEE_syn.v
syn/PE_LEE_syn.sdf
syn/PE_LEE_syn.sdc
```

---

### Synthesize `PE_array`

Use the shortcut target so the required GIN/GON/PE source list is passed correctly:

```bash
make synthesize_PE_array
```

This generates:

```text
syn/PE_array_timing_max_50_rpt.txt
syn/PE_array_timing_min_50_rpt.txt
syn/PE_array_timing_max_no_rst_rpt.txt
syn/PE_array_timing_GIN_rpt.txt
syn/PE_array_timing_GON_rpt.txt
syn/PE_array_area_rpt.txt
syn/PE_array_power_rpt.txt
syn/PE_array_syn.v
syn/PE_array_syn.sdf
syn/PE_array_syn.sdc
```

If you need to pass multiple RTL files manually, use quotes:

```bash
make synthesize SYN_TOP=PE_array SYN_SRC="src/PE_array/GIN/GIN_MulticastController.sv src/PE_array/GIN/GIN_Bus.sv src/PE_array/GIN/GIN.sv src/PE_array/GON/GON_MulticastController.sv src/PE_array/GON/GON_Bus_full_throughput_pipeline.sv src/PE_array/GON/GON_full_throughput_pipeline.sv src/PE_array/PE_LEE.sv src/PE_array/PE_array.sv" SYN_OUT=PE_array
```

---

## Output Naming Rule

The output prefix is controlled by `SYN_OUT`.

If `SYN_OUT` is not specified, the script uses `SYN_TOP` as the output prefix.

For example:

```bash
make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv
```

is equivalent to:

```bash
make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv SYN_OUT=PE
```

The generated files follow this naming rule:

```text
syn/${SYN_OUT}_timing_max_50_rpt.txt
syn/${SYN_OUT}_timing_min_50_rpt.txt
syn/${SYN_OUT}_timing_max_no_rst_rpt.txt
syn/${SYN_OUT}_timing_GIN_rpt.txt
syn/${SYN_OUT}_timing_GON_rpt.txt
syn/${SYN_OUT}_area_rpt.txt
syn/${SYN_OUT}_power_rpt.txt
syn/${SYN_OUT}_syn.v
syn/${SYN_OUT}_syn.sdf
syn/${SYN_OUT}_syn.sdc
```

---

## Shortcut Targets

The Makefile may also provide shortcut targets for common modules:

```bash
make synthesize_PE
make synthesize_PE_ori
make synthesize_PE_LEE
make synthesize_PE_array
```

These targets should internally call the same parameterized synthesis flow.

---

## Notes

- `build/` is a generated working directory and should not be committed.
- `syn/` contains generated reports, netlists, SDF files, and SDC files. Keep only the result files you need to submit or compare.
- If Design Compiler prints the Tcl commands while running, that is normal.
- Check the actual error message if synthesis fails, especially missing source paths or unset variables.

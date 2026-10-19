# VCS simulation

Run commands from this directory. The default UVM test is
`tp_read_end_to_end`.

```sh
make run
```

Run with an FSDB waveform:

```sh
make dump
```

The default waveform is written to
`wave/tp_read_end_to_end_1.fsdb`. Open it with:

```sh
make verdi
```

Seed, verbosity and dump can also be selected explicitly:

```sh
make run TEST=tp_read_end_to_end SEED=123 DUMP=1 VERBOSITY=UVM_MEDIUM
```

This focused file list registers the two stage-1 tests
`tp_read_end_to_end` and `tp_write_end_to_end`. The full
repository test package currently also pulls in stage-2/3 sources that call
`latency_gen.configure_fixed/configure_random`; those methods are absent from
the current `dv/common/latency_gen.sv`, so they are intentionally outside this
stage-1 build.

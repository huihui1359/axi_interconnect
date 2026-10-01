# VCS simulation

Run commands from this directory. The default UVM test is
`axi_stage1_single_read_test`.

```sh
make run
```

Run with an FSDB waveform:

```sh
make dump
```

The default waveform is written to
`wave/axi_stage1_single_read_test_1.fsdb`. Open it with:

```sh
make verdi
```

Seed, verbosity and dump can also be selected explicitly:

```sh
make run TEST=axi_stage1_single_read_test SEED=123 DUMP=1 VERBOSITY=UVM_MEDIUM
```

This focused file list registers the two stage-1 tests
`axi_stage1_single_read_test` and `axi_stage1_single_write_test`. The full
repository test package currently also pulls in stage-2/3 sources that call
`latency_gen.configure_fixed/configure_random`; those methods are absent from
the current `dv/common/latency_gen.sv`, so they are intentionally outside this
stage-1 build.

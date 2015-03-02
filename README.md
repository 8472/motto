Implementation of the [crisp](https://github.com/NaaS/admin/wiki/crisp) language idea,
but simplified as described in
[Flick](https://github.com/NaaS/system/tree/master/crisp/flick).

To compile:
```
$ ./build.sh
```

To run:
```
$ ./flick.byte -o output_directory source_file
```
where `output_directory` is the name of the directory (that doesn't yet
exist) that's intended to hold the compiler's output.
The compiler will create `output_directory` and deposit the output files there,
where they can be compiled and linked using a C++ toolchain.
For testing, I'm currently using `examples/hadoop_wc_type.cp` as `source_file`.

To run the parser regression tests:
```
$ ocamlrun crisp_test.byte
```

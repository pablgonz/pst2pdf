# pst2pdf &ndash; Running a PSTricks document with pdflatex

Release 0.19 2020/08/19

## Description

`pst2pdf` is a Perl script which isolates all PostScript or
PSTricks related parts of the TeX document into single
LaTeX files, for which an eps and pdf image is created.
The pdf ones are then imported in a last `pdflatex` run
for the pdf output of the main document. The eps and
pdf files are saved in a subdirectory `./images`.

## Usage

```
pst2pdf.pl [<options>] <file>[.tex|.ltx]
```

or

```
pst2pdf.pl <file>[.tex|.ltx] [<options>]
```

Relative or absolute `paths` for directories and files is not supported. Options that accept a _value_ require either a blank
space or `=` between the option and the _value_. Some short options can be bundling.

If used without `[<options>]` the extracted environments are converted to `pdf` image format
and saved in the `./images` directory using `latex>dvips>ps2pdf` and `preview` package to process `<file>`.
and `pdflatex` to process `<file-pdf>`.

## Restrictions

The `pspicture` environment can be nested, the `postscript` one **NOT!**
`pspicture` can be inside of a `postscript` environment, but
not vice versa.

```latex
\begin{postscript}
  ...
    \begin{pspicture}
      ....
    \end{pspicture}
  ...
\end{postscript}
```

The `postscript` environment should be used for all other
PostScript related commands, which are not part of
a `pspicture` environment, e.g. nodes inside normal text or `\psset{...}` outside of environment.

## Documentation

For more documentation use:

```
$ pst2pdf --help
```

or

```
$ texdoc pst2pdf
```

## Copyright

Copyright 2013 - 2020 by Herbert Voss `<hvoss@tug.org>` and Pablo González Luengo `<pablgonz@yahoo.com>`.

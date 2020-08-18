# pst2pdf &ndash; Running a PSTricks document with pdflatex

Release v0.19 \[2020-08-17\]

## Description

`pst2pdf` is a Perl _script_ which isolates all `PostScript` or `PSTricks` related
parts of the TeX document, read all `postscript`, `pspicture`, `psgraph` and `PSTexample`
environments, extract source code in standalone files and converting them into image
format \(default `pdf`\). Create new file with all extracted environments converted to `\includegraphics`
and runs \(pdf/xe/lua\)latex.

## Usage

```
pst2pdf.pl [<options>] <texfile>[.tex|.ltx]
```

or

```
pst2pdf.pl <texfile>[.tex|.ltx] [<options>]
```

Relative or absolute `paths` for directories and files is not supported. Options that accept
a _value_ require either a blank space or `=` between the option and the _value_. Some short
options can be bundling.

If used without `[<options>]` the extracted environments are converted to `pdf` image format
and saved in the `./images` directory using `latex>dvips>ps2pdf` and `preview` package to
process `<texfile>` and `pdflatex` to process the output file `<texfile-pdf>`.

## Restrictions

The `pspicture` environment can be nested, the `postscript` one **NOT!** `pspicture` can be
inside of a `postscript` environment, but not vice versa.

```latex
\begin{postscript}
  ...
    \begin{pspicture}
      ....
    \end{pspicture}
  ...
\end{postscript}
```

The `postscript` environment should be used for all other PostScript related commands, which
are not part of a `pspicture` environment, e.g. nodes inside normal text or `\psset{...}`
outside of environment.

## Installation

The script `pst2pdf` is present in `TeXLive` and `MiKTeX`, use the package manager to install.

For manual installation, download [pst2pdf.zip](http://mirrors.ctan.org/graphics/pstricks/scripts/pst2pdf.zip) and unzip it
and move all files to appropriate locations:

```
  pst2pdf-doc.pdf    -> TDS:doc/support/pst2pdf/pst2pdf-doc.pdf
  pst2pdf-doc.tex    -> TDS:doc/support/pst2pdf/pst2pdf-doc.tex
  pst2pdf-doc.bib    -> TDS:doc/support/pst2pdf/pst2pdf-doc.bib
  test1.tex          -> TDS:doc/support/pst2pdf/test1.tex
  test2.tex          -> TDS:doc/support/pst2pdf/test2.tex
  test3.tex          -> TDS:doc/support/pst2pdf/test3.tex
  test1-pdf.tex      -> TDS:doc/support/pst2pdf/test1-pdf.pdf
  test2-pdf.tex      -> TDS:doc/support/pst2pdf/test2-pdf.pdf
  test3-pdf.tex      -> TDS:doc/support/pst2pdf/test3-pdf.pdf
  tux.jpg            -> TDS:doc/support/pst2pdf/tux.jpg
  README.md          -> TDS:doc/support/pst2pdf/README.md
  Changes            -> TDS:doc/support/pst2pdf/Changes
  pst2pdf.pl         -> TDS:scripts/pst2pdf/pst2pdf.pl
```

## Documentation

For more documentation use:

```
$ pst2pdf --help
```

or

```
$ texdoc pst2pdf
```

To reproduce the documentation run `xelatex pst2pdf-doc.tex`.

## Copyright

Copyright 2013 - 2020 by Herbert Voss `<hvoss@tug.org>` and Pablo González L `<pablgonz@yahoo.com>`.

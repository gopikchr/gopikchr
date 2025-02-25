# Notes

## Changes

### commit b3e5f5a460815634be1eaf87eaaa80607126b8a9

    Add the narrow.pikchr test case.  This should have been part of
    [21ca6b843d65c404], I think.

    FossilOrigin-Name: 2fa0a525f8f246b78ee620cdc4441851c72bb98f986062fb0d88a7a1a61e3516

 tests/narrow.pikchr | 20 ++++++++++++++++++++

* copied `tests/narrow.pikchr over`

### commit 8b37a92883ceefd0588dceaeb8b65f065c2300a6

    Experimental support for the "mono" and "monospace" text attributes.

    FossilOrigin-Name: 0204bf918707fc793d0e4441c0fd954e471833db838e20cbdd980afb69202c82

 doc/differences.md         |    2 +-
 doc/grammar.md             |    2 +
 doc/textattr.md            |   11 +
 doc/userman.md             |   11 +
 fuzzcases/monospace.pikchr |    1 +
 pikchr.c                   | 1862 ++++++++++++++++++++++----------------------
 pikchr.y                   |   47 +-
 tests/test40.pikchr        |    2 +-
 tests/test45.pikchr        |    3 +-

* Copied code over; updated tests

### commit 90342052ad7ae93f49f6eae66efece1dac498501

    "mono italic" test case added.

    FossilOrigin-Name: fc34d765e110d2b1dba6d7037455494a46a6e2ae4a39fe5d4056217c82ce369b

 tests/test45.pikchr | 2 +-

* only a test was updated; easy!

### commit dbb1ae84d63db0512aee45c89286aed7580925c4

    Adjust the font size and text length computations for monospace.

    FossilOrigin-Name: 22e2a2c622aa8186d963c5de23e8bc39217b73628affacd5f661e51106156488

 pikchr.c            | 5 +++--
 pikchr.y            | 3 ++-
 tests/test45.pikchr | 2 +-

* Copied the changes over

### commit 39d140c780320f103d19366e4520f175d20812ac

    Remove the artificial enlargement of "mono" text, as that seems not to be
    necessary when the output is rendered by Fossil.  Must be some kind of CSS
    issue.

    FossilOrigin-Name: 03664a38cfb8053340ba733219a2d7ab74d45f10ba32a75f5fb72221238a193f

 pikchr.c | 3 +--
 pikchr.y | 1 -

* Undid 128% extra size for monospaced font

### commit 511e98a82140dcce0174cbe6f98bc24e801f2354

    It seems like the "same" operator should not mess with layout direction.
    See [/forumpost/75a2220c44|forum thread 75a2220c44].

    FossilOrigin-Name: 62b766efe8faea55ef137eeda907c7156a346ced1f620c6ca57c16c9bc45fc84

 pikchr.c             |  4 +---
 pikchr.y             |  2 --
 tests/fonts01.pikchr | 54 ++++++++++++++++++++++++++++++++++++++++++++++++++++
 tests/test77.pikchr  | 11 +++++++++++

* Made the corresponding changes to not override direction

### commit 2d7ef88fa8a116b86e8988e10a2258f626c4d1a5

    Zero-thickness objects draw the background but not the outline.

    FossilOrigin-Name: f30f1fe1869661543d3a908322ab9ce801cdb2455b5faa4965b85c394ef3f8c2

 pikchr.c | 28 ++++++++++++++++------------
 pikchr.y | 26 +++++++++++++++-----------

* Copied updates over. Mostly `s/>0.0/>=0.0/`

### commit b2145bf3f7d16f3650e6d3208b22d3de9d895672

    Fix text positioning of lines with negative thickness.

    FossilOrigin-Name: 5b5ad53f2709eace79d2c8f4dd7cf3a4000c23ab85a52c5cf127638386933682

 pikchr.c            | 7 ++++---
 pikchr.y            | 5 +++--
 tests/test78.pikchr | 8 ++++++++
 tests/test79.pikchr | 7 +++++++

* Mostly careful use around zero of `sw` variables

### commit cf7a53d073f55251a699b3a6c19080c99713fc2f

    Enhanced a test case so that it shows compass points for "file" objects.

    FossilOrigin-Name: d6f80b1ab30654d5124557fd64770799e51038c579fd1c5432c1ab6549a275a5

 tests/test41.pikchr | 10 ++++++++++

* Just a test to copy over

### commit 0f1e8a45ff69ac00fc20ce89149f879932d24edb

    Increase an snprintf() output buffer size by a few bytes to squelch a warning from gcc 12.2 reported in fossil /chat.

    FossilOrigin-Name: 4bb035e213b01d3acc11ec37902b55787844e851e7bdfad15d9fd7fbe0677f58

 pikchr.c | 2 +-
 pikchr.y | 2 +-

* Nothing changed in the Go version

### commit a89d4c702c4253d959b9513b0c60fa8704c78a49

    Add support for the "diamond" primitive.

    FossilOrigin-Name: 36751abee2b04be56c8d470e66c83933df57de6396a9f019bf41d783763e2a3c

 pikchr.c                | 67 ++++++++++++++++++++++++++++++++++++++++++++++++-
 pikchr.y                | 65 +++++++++++++++++++++++++++++++++++++++++++++++
 tests/autochop10.pikchr | 38 ++++++++++++++++++++++++++++
 tests/diamond01.pikchr  | 14 +++++++++++
 tests/test78.pikchr     |  1 +

* Translated the code over. Same style as code beside it.

### commit 8e6d5c106e3d99a2d15a7927b3ad45f25477c0d1

    Replaced the macro form of "diamond" in test71.pikchr with native Pikchr
    diamonds.  Rigorous regression testing would flag a change like this for
    a difference in the SVG output, but we don't have that in this project;
    "make test" merely opens the result of rendering this file and others in
    an HTML page for visual inspection.

    Another way of justifying this commit, therefore, is that it fixes
    syntax errors in the test output, owing to the recent elevation of
    "diamond" to a keyword.

    FossilOrigin-Name: 48f60266386dcf07a88b3c5f550e901675a2b9dac4529e7cdfb44afa8d081740

 tests/test71.pikchr | 11 +++--------

* Just copied the test over

### commit f1836afa1121649b7001f1bdbba5727cea66a76a

    Update the built-in Lemon parser to the latest version.

    FossilOrigin-Name: 24c702e82cff7c01b8c2a87a6cfc7305ccfb03f9465835367f82c0659c2ebaa9

 lemon.c  |  80 ++++++++++++--
 lempar.c | 132 +++++++++++++----------
 pikchr.c | 370 ++++++++++++++++++++++++++++++++++-----------------------------

* Nothing to do - we use golemon

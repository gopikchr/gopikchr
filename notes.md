# Notes

## Changes

### commit 35970d0b70fdaf351cc6822fef49f39e2c21da0a

    Improved boundry box estimation for arcs.  Response to
    [/forumpost/ed93cba38db85818|forum post ed93cba38d].

    FossilOrigin-Name: 9b9b3133644ff804f8312bb839ad4eb43d1eb1869558f7a3a50b788b2c4a706a

 pikchr.y | 12 +++++++-----

* Added `rPct` parameter to arcControlPoint() function
* Changed midpoint calculation from fixed 0.5 to use rPct parameter
* In arcCheck(), now computes control points at 0.25 and 0.75 and adds both to bounding box
* In arcRender(), updated call to pass 0.5 as rPct parameter
* Improves bounding box estimation for arc objects
* Tests pass: C and Go produce identical output

### commit 41c1d846af49e765772cb24238d25a2ae75d7a59

    Change the output of pikchr_version() to omit all punctuation from the
    date, so that the date is just a 14-digit integer.

    FossilOrigin-Name: bb99465bd126646c031c7426f05e8b85c6f170a4af76d603b25d3aaeb749de31

 pikchr.y | 2 +-

* Changed PikChrVersion() to return ManifestISODate instead of ManifestDate
* Version string format changed from "1.0 2025-03-05 10:44:08" to "1.0 20250305"
* Updated ManifestDate and ManifestISODate constants to "2025-03-05 10:44:08" and "20250305"
* Tests pass: C and Go produce identical output
* Example: PikChrVersion() now outputs "1.0 20250305" (14-digit integer date)

### commit 9c5ced3599ce4f99b113b87a9be6d00ac1b95cc0

    The magic "pikchr_date" token behaves like a string which expands to the
    ISO date of the check-in.  Useful for debugging and to determine exactly
    which pikchr version is running.

    FossilOrigin-Name: 96d37690a60d8a7d9b79b1f22591ba8a02704af922b8b2a38551489dad8d9963

 pikchr.c | 2412 +++++++++++++++++++++++++++++++-------------------------------
 pikchr.y |   13 +-

* Renamed "pikchr_isodate" keyword to "pikchr_date" (T_PIKCHRISODATE → T_ISODATE)
* Removed grammar rule `pritem ::= PIKCHRISODATE` - now handled in tokenizer
* Added `%token ISODATE` declaration
* Token conversion: T_ISODATE is converted to T_STRING with quoted date value in tokenizer
* Updated ManifestISODate constant to "20250305"
* Updated c/VERSION.h with new date
* Updated golemon lemonc to support `%include <file>` syntax (copied from pikchr lemon.c)
* Tests pass: C and Go produce identical output
* Example: "print pikchr_date" outputs "20250305"

### commit 95576ac6b08b913814489da50e9552c4c4a714df

    Add a change log.  Already has a 1.1 entry even though we are not there
    yet.  Add the "pikchr_isodate" keyword which can be an argument to "print".

    FossilOrigin-Name: 918b2b57f20b9836d88ce1dd6fd86d231ec9193151215583b8728d72c3caa9e5

 doc/changelog.md |   19 +
 homepage.md      |    1 +
 pikchr.c         | 2848 +++++++++++++++++++++++++++------------------------
 pikchr.y         |    8 +-

* Added T_PIKCHRISODATE token
* Added "pikchr_isodate" keyword to keyword list
* Added grammar rule: pritem ::= PIKCHRISODATE
* pikchr_isodate outputs ManifestISODate constant in print statements
* Tests pass: C and Go produce identical output
* Example: "print pikchr_isodate" outputs "20250304"

### commit b5fd83b519ea5a56ad274621222cf1a3c2fda9eb

    Include the check-in date as a data-* field on the &lt;svg&gt; element.

    FossilOrigin-Name: 5c738ded0e10e6102d7ce0e6a5db9e6fb3cdc484442e7d6d0eba65b85b9c2740

 pikchr.c | 5 +++--
 pikchr.y | 3 ++-

* Added ManifestISODate constant to internal/pikchr.y
* Updated SVG output to include data-pikchr-date attribute
* Updated c/VERSION.h with MANIFEST_ISODATE definition
* Tests pass: C and Go produce identical output
* Output includes: data-pikchr-date="20250304"

### commit 5413136dfa096c393aaf2bc7d6fc4b6ef7b2fce1

    Add the pikchr_version() interface which returns a string constant that
    describe the release version number and the date/time of the check-in.

    FossilOrigin-Name: 7ba88e2dd73c92ad933bfd0dbe098b9bf795fa76b3efa2edd9bdd1a684ab84c7

 Makefile     |   6 +-
 Makefile.msc |   6 +-
 VERSION      |   1 +
 mkversion.c  | 193 +++++++++++++++++++++++++
 pikchr.c     | 470 +++++++++++++++++++++++++++++++++--------------------------
 pikchr.h     |   4 +
 pikchr.h.in  |   4 +
 pikchr.y     |  12 ++

* Added version constants (ReleaseVersion, ManifestDate) to internal/pikchr.y
* Added PikChrVersion() function to internal package
* Added Version() exported function to gopikchr package
* Added --version/-v flags to cmd/gopikchr
* Created c/VERSION.h for C build compatibility
* Tests pass: C and Go produce identical output

### commit fb45ee9990872c03ea7fb24fec54196e7bbd4bf9

    Fix a bug (reported by [forumpost/f9f5d90f33|forum post f9f5d90f33]) in
    which the "with EDGE at POSITION" layout causes the object to be "fit"
    if POSITION refers to a "text" object.

    FossilOrigin-Name: d34295b192c40f935113cb764f9f6c39b124d845952aac82fdff67915f7d17c4

 pikchr.c            | 19 +++++++++----------
 pikchr.y            | 17 ++++++++---------
 tests/test81.pikchr |  5 +++++

* Added pObj parameter to pik_size_to_fit() function signature
* Updated all call sites (5 total) to pass pObj explicitly or nil
* Copied test81.pikchr test case
* Tests pass: C and Go produce identical output

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

### commit 2dd37320c37df41c282b1388fb6b7377650ba533

    Update a test case to include a diamond object.

    FossilOrigin-Name: fd78aef978b65ed0de7d425b0f4a672cf98814fe192d259a378ab649bab8ecb1

 tests/test41.pikchr | 10 ++++++++++

* Just copied the test over

### commit d7ae70d3200d0c8f44db3ec55fe54c7b91a9bf0d

    Fix the autofit functionality for the diamond object.  New test cases for
    the same.

    FossilOrigin-Name: ad1f8186cd90dc65b21bea897a7efd005200cba4ef1832334a0873eff9f92fa1

 pikchr.c            | 470 ++++++++++++++++++++++++++--------------------------
 pikchr.y            |  12 +-
 tests/test54.pikchr |   6 +-
 tests/test65.pikchr |  12 ++

* Translated the code on over.

### commit 77b06d99c8502beecf414ebf4cdfb3d07e2e20ba

    For the "pikchr" command-line tool, the --dont-stop flag always results in
    a zero exit code.  Fix the MSVC Makefile so that "nmake test" works.

    FossilOrigin-Name: ac94035c3223dd27a0c9429ff27945ebe6f7db4649eb565f97cb7c71e4979e8a

 Makefile     |  6 +++---
 Makefile.msc | 24 +++++++++++++++++-------
 pikchr.c     |  5 +++--
 pikchr.y     |  3 ++-

* Changes to the CLI actually live in `cmd/gopikchr/gopikchr.go

### commit 9fb6a77c71a9931847d5b94113fad10fc51de9b1

    Fix (harmless) typos reported by [/forumpost/3a76eb4395|forum post 3a76eb4395].

    FossilOrigin-Name: ae3317b0ec2e635cb14ff65ff4225a5647533d48d5dcc9831fd0268792a2b09d

 pikchr.c | 4 ++--
 pikchr.y | 4 ++--

* Nothing to do here.

### commit 45ae9fdb0d026153ec96fcee783050dacae4ca80

    Fix the behavior of "with .start". [/forumpost/a48fbe155b|Forum post a48fbe155b]

    FossilOrigin-Name: e79028e18dce9f2c089e69aa33012ee214026b6a1ca97c42e20d8e46fdc92b3b

 pikchr.c            |  2 +-
 pikchr.y            |  2 +-
 tests/test80.pikchr | 30 ++++++++++++++++++++++++++++++

* Copied the small change over

### commit e3576f06ea0044f48f0289e6639f0d284425f8c7

    Add "style='font-size:100%'" to the &lt;svg&gt; element to work around an
    issue in Safari.  [/forumpost/8c9e9aa984|Forum post 8c9e9aa984].

    FossilOrigin-Name: 67d1cab26b5b812f2a046318a8269655fe0bc3f52abac29bc3b8dfc537609cc8

 pikchr.c | 5 +++--
 pikchr.y | 3 ++-

* Copy the SVG tag change over

### commit 0624fc4904a9c8d628d8e4ede7386b590d123d68

    In the previous check-in, a better value for font-size is "initial".

    FossilOrigin-Name: 1562bd171ab868db152cffc7c0c2aca9dc416ef5acd66e8de6d9d6a0b9ebeff6

 pikchr.c | 2 +-
 pikchr.y | 2 +-

* Copy the fix over

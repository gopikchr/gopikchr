%include {
/*
** Zero-Clause BSD license:
**
** Copyright (C) 2020-09-01 by D. Richard Hipp <drh@sqlite.org>
**
** Permission to use, copy, modify, and/or distribute this software for
** any purpose with or without fee is hereby granted.
**
****************************************************************************
**
** This software translates a PIC-inspired diagram language into SVG.
**
** PIKCHR (pronounced like "picture") is *mostly* backwards compatible
** with legacy PIC, though some features of legacy PIC are removed
** (for example, the "sh" command is removed for security) and
** many enhancements are added.
**
** PIKCHR is designed for use in an internet facing web environment.
** In particular, PIKCHR is designed to safely generate benign SVG from
** source text that provided by a hostile agent.
**
** This code was originally written by D. Richard Hipp using documentation
** from prior PIC implementations but without reference to prior code.
** All of the code in this project is original.
**
** This file implements a C-language subroutine that accepts a string
** of PIKCHR language text and generates a second string of SVG output that
** renders the drawing defined by the input.  Space to hold the returned
** string is obtained from malloc() and should be freed by the caller.
** NULL might be returned if there is a memory allocation error.
**
** If there are errors in the PIKCHR input, the output will consist of an
** error message and the original PIKCHR input text (inside of <pre>...</pre>).
**
** The subroutine implemented by this file is intended to be stand-alone.
** It uses no external routines other than routines commonly found in
** the standard C library.
**
****************************************************************************
** COMPILING:
**
** The original source text is a mixture of C99 and "Lemon"
** (See https://sqlite.org/src/file/doc/lemon.html).  Lemon is an LALR(1)
** parser generator program, similar to Yacc.  The grammar of the
** input language is specified in Lemon.  C-code is attached.  Lemon
** runs to generate a single output file ("pikchr.c") which is then
** compiled to generate the Pikchr library.  This header comment is
** preserved in the Lemon output, so you might be reading this in either
** the generated "pikchr.c" file that is output by Lemon, or in the
** "pikchr.y" source file that is input into Lemon.  If you make changes,
** you should change the input source file "pikchr.y", not the
** Lemon-generated output file.
**
** Basic compilation steps:
**
**      lemon pikchr.y
**      cc pikchr.c -o pikchr.o
**
** Add -DPIKCHR_SHELL to add a main() routine that reads input files
** and sends them through Pikchr, for testing.  Add -DPIKCHR_FUZZ for
** -fsanitizer=fuzzer testing.
**
****************************************************************************
** IMPLEMENTATION NOTES (for people who want to understand the internal
** operation of this software, perhaps to extend the code or to fix bugs):
**
** Each call to pikchr() uses a single instance of the Pik structure to
** track its internal state.  The Pik structure lives for the duration
** of the pikchr() call.
**
** The input is a sequence of objects or "statements".  Each statement is
** parsed into a PObj object.  These are stored on an extensible array
** called PList.  All parameters to each PObj are computed as the
** object is parsed.  (Hence, the parameters to a PObj may only refer
** to prior statements.) Once the PObj is completely assembled, it is
** added to the end of a PList and never changes thereafter - except,
** PObj objects that are part of a "[...]" block might have their
** absolute position shifted when the outer [...] block is positioned.
** But apart from this repositioning, PObj objects are unchanged once
** they are added to the list. The order of statements on a PList does
** not change.
**
** After all input has been parsed, the top-level PList is walked to
** generate output.  Sub-lists resulting from [...] blocks are scanned
** as they are encountered.  All input must be collected and parsed ahead
** of output generation because the size and position of statements must be
** known in order to compute a bounding box on the output.
**
** Each PObj is on a "layer".  (The common case is that all PObj's are
** on a single layer, but multiple layers are possible.)  A separate pass
** is made through the list for each layer.
**
** After all output is generated, the Pik object and all the PList
** and PObj objects are deallocated and the generated output string is
** returned.  Upon any error, the Pik.nErr flag is set, processing quickly
** stops, and the stack unwinds.  No attempt is made to continue reading
** input after an error.
**
** Most statements begin with a class name like "box" or "arrow" or "move".
** There is a class named "text" which is used for statements that begin
** with a string literal.  You can also specify the "text" class.
** A Sublist ("[...]") is a single object that contains a pointer to
** its substatements, all gathered onto a separate PList object.
**
** Variables go into PVar objects that form a linked list.
**
** Each PObj has zero or one names.  Input constructs that attempt
** to assign a new name from an older name, for example:
**
**      Abc:  Abc + (0.5cm, 0)
**
** Statements like these generate a new "noop" object at the specified
** place and with the given name. As place-names are searched by scanning
** the list in reverse order, this has the effect of overriding the "Abc"
** name when referenced by subsequent objects.
*/

package internal

import (
	"bytes"
	"fmt"
	"io"
	"math"
	"os"
	"regexp"
	"strconv"
	"strings"
)

// Version information
const (
	ReleaseVersion   = "1.0"
	ManifestDate     = "2025-03-05 00:29:51"  // Upstream commit date
	ManifestISODate  = "20250305"             // ISO date format (YYYYMMDD)
)

// Numeric value
type PNum = float64

// Compass points
const (
  CP_N uint8 =  iota+1
  CP_NE
  CP_E
  CP_SE
  CP_S
  CP_SW
  CP_W
  CP_NW
  CP_C     /* .center or .c */
  CP_END   /* .end */
  CP_START /* .start */
)

const PIKCHR_TOKEN_LIMIT = 100000

/* Heading angles corresponding to compass points */
var pik_hdg_angle = []PNum{
/* none  */   0.0,
  /* N  */    0.0,
  /* NE */   45.0,
  /* E  */   90.0,
  /* SE */  135.0,
  /* S  */  180.0,
  /* SW */  225.0,
  /* W  */  270.0,
  /* NW */  315.0,
  /* C  */    0.0,
}

/* Built-in functions */
const (
  FN_ABS =    0
  FN_COS =    1
  FN_INT =    2
  FN_MAX =    3
  FN_MIN =    4
  FN_SIN =    5
  FN_SQRT =   6
)

/* Text position and style flags.  Stored in PToken.eCode so limited
** to 15 bits. */
const (
  TP_LJUST =   0x0001  /* left justify......          */
  TP_RJUST =   0x0002  /*            ...Right justify */
  TP_JMASK =   0x0003  /* Mask for justification bits */
  TP_ABOVE2 =  0x0004  /* Position text way above PObj.ptAt */
  TP_ABOVE =   0x0008  /* Position text above PObj.ptAt */
  TP_CENTER =  0x0010  /* On the line */
  TP_BELOW =   0x0020  /* Position text below PObj.ptAt */
  TP_BELOW2 =  0x0040  /* Position text way below PObj.ptAt */
  TP_VMASK =   0x007c  /* Mask for text positioning flags */
  TP_BIG =     0x0100  /* Larger font */
  TP_SMALL =   0x0200  /* Smaller font */
  TP_XTRA =    0x0400  /* Amplify TP_BIG or TP_SMALL */
  TP_SZMASK =  0x0700  /* Font size mask */
  TP_ITALIC =  0x1000  /* Italic font */
  TP_BOLD =    0x2000  /* Bold font */
  TP_MONO =    0x4000  /* Monospace font family */
  TP_FMASK =   0x7000  /* Mask for font style */
  TP_ALIGN =  -0x8000  /* Rotate to align with the line */
)

/* An object to hold a position in 2-D space */
type PPoint struct {
  /* X and Y coordinates */
  x PNum
  y PNum
}

/* A bounding box */
type PBox struct {
  /* Lower-left and top-right corners */
  sw PPoint
  ne PPoint
}

/* An Absolute or a relative distance.  The absolute distance
** is stored in rAbs and the relative distance is stored in rRel.
** Usually, one or the other will be 0.0.  When using a PRel to
** update an existing value, the computation is usually something
** like this:
**
**          value = PRel.rAbs + value*PRel.rRel
**
*/
type PRel struct {
  rAbs PNum            /* Absolute value */
  rRel PNum            /* Value relative to current value */
}

/* A variable created by the ID = EXPR construct of the PIKCHR script
**
** PIKCHR (and PIC) scripts do not use many varaibles, so it is reasonable
** to store them all on a linked list.
*/
type PVar struct {
  zName string            /* Name of the variable */
  val PNum                /* Value of the variable */
  pNext *PVar             /* Next variable in a list of them all */
}

/* A single token in the parser input stream
*/
type PToken struct {
  z []byte                   /* Pointer to the token text */
  n int                      /* Length of the token in bytes */

  eCode int16                /* Auxiliary code */
  eType uint8                /* The numeric parser code */
  eEdge uint8                /* Corner value for corner keywords */
}

func (p PToken) String() string {
  return string(p.z[:p.n])
}

/* Return negative, zero, or positive if pToken is less than, equal to
** or greater than the zero-terminated string z[]
*/
func pik_token_eq(pToken *PToken, z string) int {
  c := bytencmp(pToken.z, z, pToken.n)
  if c == 0 && len(z) > pToken.n && z[pToken.n] != 0 { c = -1 }
  return c
}

/* Extra token types not generated by LEMON but needed by the
** tokenizer
*/
const (
  T_PARAMETER =  253     /* $1, $2, ..., $9 */
  T_WHITESPACE = 254     /* Whitespace of comments */
  T_ERROR =      255     /* Any text that is not a valid token */
)

/* Directions of movement */
const (
  DIR_RIGHT =   0
  DIR_DOWN =    1
  DIR_LEFT =    2
  DIR_UP =      3
)

func ValidDir(x uint8) bool {
  return x >= 0 && x <= 3
}

func IsUpDown(x uint8) bool {
  return x&1 == 1
}

func IsLeftRight(x uint8) bool {
  return x&1 == 0
}

/* Bitmask for the various attributes for PObj.  These bits are
** collected in PObj.mProp and PObj.mCalc to check for constraint
** errors. */
const (
  A_WIDTH =       0x0001
  A_HEIGHT =      0x0002
  A_RADIUS =      0x0004
  A_THICKNESS =   0x0008
  A_DASHED =      0x0010 /* Includes "dotted" */
  A_FILL =        0x0020
  A_COLOR =       0x0040
  A_ARROW =       0x0080
  A_FROM =        0x0100
  A_CW =          0x0200
  A_AT =          0x0400
  A_TO =          0x0800 /* one or more movement attributes */
  A_FIT =         0x1000
)

/* A single graphics object */
type PObj struct {
  typ *PClass              /* Object type or class */
  errTok PToken            /* Reference token for error messages */
  ptAt PPoint              /* Reference point for the object */
  ptEnter PPoint           /* Entry and exit points */
  ptExit PPoint
  pSublist []*PObj          /* Substructure for [...] objects */
  zName string             /* Name assigned to this statement */
  w PNum                   /* "width" property */
  h PNum                   /* "height" property */
  rad PNum                 /* "radius" property */
  sw PNum                  /* "thickness" property. (Mnemonic: "stroke width")*/
  dotted PNum              /* "dotted" property.   <=0.0 for off */
  dashed PNum              /* "dashed" property.   <=0.0 for off */
  fill PNum                /* "fill" property.  Negative for off */
  color PNum               /* "color" property */
  with PPoint              /* Position constraint from WITH clause */
  eWith uint8              /* Type of heading point on WITH clause */
  cw bool                  /* True for clockwise arc */
  larrow bool              /* Arrow at beginning (<- or <->) */
  rarrow bool              /* Arrow at end  (-> or <->) */
  bClose bool              /* True if "close" is seen */
  bChop bool               /* True if "chop" is seen */
  bAltAutoFit bool         /* Always send both h and w into xFit() */
  nTxt uint8               /* Number of text values */
  mProp uint               /* Masks of properties set so far */
  mCalc uint               /* Values computed from other constraints */
  aTxt [5]PToken           /* Text with .eCode holding TP flags */
  iLayer int               /* Rendering order */
  inDir uint8              /* Entry and exit directions */
  outDir uint8
  nPath int                /* Number of path points */
  aPath []PPoint           /* Array of path points */
  pFrom *PObj              /* End-point objects of a path */
  pTo *PObj
  bbox PBox                /* Bounding box */
}

// /* A list of graphics objects */
// type PList struct {
//   int n;          /* Number of statements in the list */
//   int nAlloc;     /* Allocated slots in a[] */
//   PObj **a;       /* Pointers to individual objects */
// };
type PList = []*PObj

/* A macro definition */
type PMacro struct {
  pNext *PMacro        /* Next in the list */
  macroName PToken     /* Name of the macro */
  macroBody PToken     /* Body of the macro */
  inUse bool           /* Do not allow recursion */
}

/* Each call to the pikchr() subroutine uses an instance of the following
** object to pass around context to all of its subroutines.
*/
type Pik struct {
  nErr int                 /* Number of errors seen */
  nToken uint              /* Number of tokens parsed */
  sIn PToken               /* Input Pikchr-language text */
  zOut bytes.Buffer        /* Result accumulates here */
  nOut uint                /* Bytes written to zOut[] so far */
  nOutAlloc uint           /* Space allocated to zOut[] */
  eDir uint8               /* Current direction */
  mFlags uint              /* Flags passed to pikchr() */
  cur *PObj                /* Object under construction */
  lastRef *PObj            /* Last object references by name */
  list []*PObj             /* Object list under construction */
  pMacros *PMacro          /* List of all defined macros */
  pVar *PVar               /* Application-defined variables */
  bbox PBox                /* Bounding box around all statements */
                           /* Cache of layout values.  <=0.0 for unknown... */
  rScale PNum                  /* Multiply to convert inches to pixels */
  fontScale PNum               /* Scale fonts by this percent */
  charWidth PNum               /* Character width */
  charHeight PNum              /* Character height */
  wArrow PNum                  /* Width of arrowhead at the fat end */
  hArrow PNum                  /* Ht of arrowhead - dist from tip to fat end */
  bLayoutVars bool             /* True if cache is valid */
  thenFlag bool            /* True if "then" seen */
  samePath bool            /* aTPath copied by "same" */
  zClass string            /* Class name for the <svg> */
  wSVG int                 /* Width and height of the <svg> */
  hSVG int
  fgcolor int              /* foreground color value, or -1 for none */
  bgcolor int              /* background color value, or -1 for none */
  /* Paths for lines are constructed here first, then transferred into
  ** the PObj object at the end: */
  nTPath int               /* Number of entries on aTPath[] */
  mTPath int               /* For last entry, 1: x set,  2: y set */
  aTPath [1000]PPoint      /* Path under construction */
  /* Error contexts */
  nCtx int                /* Number of error contexts */
  aCtx [10]PToken          /* Nested error contexts */
}

/* Include PIKCHR_PLAINTEXT_ERRORS among the bits of mFlags on the 3rd
** argument to pikchr() in order to cause error message text to come out
** as text/plain instead of as text/html
*/
const PIKCHR_PLAINTEXT_ERRORS = 0x0001

/* Include PIKCHR_DARK_MODE among the mFlag bits to invert colors.
*/
const PIKCHR_DARK_MODE =        0x0002

/*
** The behavior of an object class is defined by an instance of
** this structure. This is the "virtual method" table.
*/
type PClass struct {
  zName string                            /* Name of class */
  isLine bool                             /* True if a line class */
  eJust int8                              /* Use box-style text justification */

  xInit func(*Pik, *PObj)                  /* Initializer */
  xNumProp func(*Pik,*PObj,*PToken)      /* Value change notification */
  xCheck func(*Pik,*PObj)                 /* Checks to do after parsing */
  xChop func(*Pik,*PObj,*PPoint) PPoint   /* Chopper */
  xOffset func(*Pik,*PObj,uint8) PPoint     /* Offset from .c to edge point */
  xFit func(pik *Pik, pobj *PObj,w PNum,h PNum)     /* Size to fit text */
  xRender func(*Pik,*PObj)                /* Render */
}

func yytestcase(condition bool) {}

} // end %include

%name pik_parser
%token_prefix T_
%token_type {PToken}
%extra_context {p *Pik}

%fallback ID EDGEPT.

// precedence rules.
%left OF.
%left PLUS MINUS.
%left STAR SLASH PERCENT.
%right UMINUS.

%type statement_list {[]*PObj}
%destructor statement_list {p.pik_elist_free(&$$)}
%type statement {*PObj}
%destructor statement {p.pik_elem_free($$)}
%type unnamed_statement {*PObj}
%destructor unnamed_statement {p.pik_elem_free($$)}
%type basetype {*PObj}
%destructor basetype {p.pik_elem_free($$)}
%type expr {PNum}
%type numproperty {PToken}
%type edge {PToken}
%type direction {PToken}
%type dashproperty {PToken}
%type colorproperty {PToken}
%type locproperty {PToken}
%type position {PPoint}
%type place {PPoint}
%type object {*PObj}
%type objectname {*PObj}
%type nth {PToken}
%type textposition {int}
%type rvalue {PNum}
%type lvalue {PToken}
%type even {PToken}
%type relexpr {PRel}
%type optrelexpr {PRel}

%syntax_error {
  if TOKEN.z != nil && TOKEN.z[0] != 0 {
    p.pik_error(&TOKEN, "syntax error")
  }else{
    p.pik_error(nil, "syntax error")
  }
}
%stack_overflow {
  p.pik_error(nil, "parser stack overflow")
}

document ::= statement_list(X).  {p.pik_render(X)}


statement_list(A) ::= statement(X).   { A = p.pik_elist_append(nil,X) }
statement_list(A) ::= statement_list(B) EOL statement(X).
                      { A = p.pik_elist_append(B,X) }


statement(A) ::= .   { A = nil }
statement(A) ::= direction(D).  { p.pik_set_direction(uint8(D.eCode));  A=nil }
statement(A) ::= lvalue(N) ASSIGN(OP) rvalue(X). {p.pik_set_var(&N,X,&OP); A=nil}
statement(A) ::= PLACENAME(N) COLON unnamed_statement(X).
               { A = X;  p.pik_elem_setname(X,&N) }
statement(A) ::= PLACENAME(N) COLON position(P).
               { A = p.pik_elem_new(nil,nil,nil)
                 if A!=nil { A.ptAt = P; p.pik_elem_setname(A,&N) }}
statement(A) ::= unnamed_statement(X).  {A = X}
statement(A) ::= print prlist.  {p.pik_append("<br>\n"); A=nil}

// assert() statements are undocumented and are intended for testing and
// debugging use only.  If the equality comparison of the assert() fails
// then an error message is generated.
statement(A) ::= ASSERT LP expr(X) EQ(OP) expr(Y) RP. {A=p.pik_assert(X,&OP,Y)}
statement(A) ::= ASSERT LP position(X) EQ(OP) position(Y) RP.
                                          {A=p.pik_position_assert(&X,&OP,&Y)}
statement(A) ::= DEFINE ID(ID) CODEBLOCK(C).  {A=nil; p.pik_add_macro(&ID,&C)}

lvalue(A) ::= ID(A).
lvalue(A) ::= FILL(A).
lvalue(A) ::= COLOR(A).
lvalue(A) ::= THICKNESS(A).

// PLACENAME might actually be a color name (ex: DarkBlue).  But we
// cannot make it part of expr due to parsing ambiguities.  The
// rvalue non-terminal means "general expression or a colorname"
rvalue(A) ::= expr(A).
rvalue(A) ::= PLACENAME(C).  {A = p.pik_lookup_color(&C)}

print ::= PRINT.
prlist ::= pritem.
prlist ::= prlist prsep pritem.
pritem ::= FILL(X).        {p.pik_append_num("",p.pik_value(X.String(),nil))}
pritem ::= COLOR(X).       {p.pik_append_num("",p.pik_value(X.String(),nil))}
pritem ::= THICKNESS(X).   {p.pik_append_num("",p.pik_value(X.String(),nil))}
pritem ::= rvalue(X).      {p.pik_append_num("",X)}
pritem ::= STRING(S).      {p.pik_append_text(string(S.z[1:S.n-1]),0)}
prsep  ::= COMMA.          {p.pik_append(" ")}

%token ISODATE.

unnamed_statement(A) ::= basetype(X) attribute_list.
                          {A = X; p.pik_after_adding_attributes(A)}

basetype(A) ::= CLASSNAME(N).            {A = p.pik_elem_new(&N,nil,nil) }
basetype(A) ::= STRING(N) textposition(P).
                            {N.eCode = int16(P); A = p.pik_elem_new(nil,&N,nil) }
basetype(A) ::= LB savelist(L) statement_list(X) RB(E).
  { p.list = L; A = p.pik_elem_new(nil,nil,X); if A!=nil {A.errTok = E} }

%type savelist {[]*PObj}
// No destructor required as this same PList is also held by
// an "statement" non-terminal deeper on the stack.
savelist(A) ::= .   {A = p.list; p.list = nil}

direction(A) ::= UP(A).
direction(A) ::= DOWN(A).
direction(A) ::= LEFT(A).
direction(A) ::= RIGHT(A).

relexpr(A) ::= expr(B).             {A.rAbs = B; A.rRel = 0}
relexpr(A) ::= expr(B) PERCENT.     {A.rAbs = 0; A.rRel = B/100}
optrelexpr(A) ::= relexpr(A).
optrelexpr(A) ::= .                 {A.rAbs = 0; A.rRel = 1.0}

attribute_list ::= relexpr(X) alist.    {p.pik_add_direction(nil,&X)}
attribute_list ::= alist.
alist ::=.
alist ::= alist attribute.
attribute ::= numproperty(P) relexpr(X).     { p.pik_set_numprop(&P,&X) }
attribute ::= dashproperty(P) expr(X).       { p.pik_set_dashed(&P,&X) }
attribute ::= dashproperty(P).               { p.pik_set_dashed(&P,nil);  }
attribute ::= colorproperty(P) rvalue(X).    { p.pik_set_clrprop(&P,X) }
attribute ::= go direction(D) optrelexpr(X). { p.pik_add_direction(&D,&X)}
attribute ::= go direction(D) even position(P). {p.pik_evenwith(&D,&P)}
attribute ::= CLOSE(E).             { p.pik_close_path(&E) }
attribute ::= CHOP.                 { p.cur.bChop = true }
attribute ::= FROM(T) position(X).  { p.pik_set_from(p.cur,&T,&X) }
attribute ::= TO(T) position(X).    { p.pik_add_to(p.cur,&T,&X) }
attribute ::= THEN(T).              { p.pik_then(&T, p.cur) }
attribute ::= THEN(E) optrelexpr(D) HEADING(H) expr(A).
                                                {p.pik_move_hdg(&D,&H,A,nil,&E)}
attribute ::= THEN(E) optrelexpr(D) EDGEPT(C).  {p.pik_move_hdg(&D,nil,0,&C,&E)}
attribute ::= GO(E) optrelexpr(D) HEADING(H) expr(A).
                                                {p.pik_move_hdg(&D,&H,A,nil,&E)}
attribute ::= GO(E) optrelexpr(D) EDGEPT(C).    {p.pik_move_hdg(&D,nil,0,&C,&E)}
attribute ::= boolproperty.
attribute ::= AT(A) position(P).                    { p.pik_set_at(nil,&P,&A) }
attribute ::= WITH withclause.
attribute ::= SAME(E).                          {p.pik_same(nil,&E)}
attribute ::= SAME(E) AS object(X).             {p.pik_same(X,&E)}
attribute ::= STRING(T) textposition(P).        {p.pik_add_txt(&T,int16(P))}
attribute ::= FIT(E).                           {p.pik_size_to_fit(nil,&E,3) }
attribute ::= BEHIND object(X).                 {p.pik_behind(X)}

go ::= GO.
go ::= .

even ::= UNTIL EVEN WITH.
even ::= EVEN WITH.

withclause ::=  DOT_E edge(E) AT(A) position(P).{ p.pik_set_at(&E,&P,&A) }
withclause ::=  edge(E) AT(A) position(P).      { p.pik_set_at(&E,&P,&A) }

// Properties that require an argument
numproperty(A) ::= HEIGHT|WIDTH|RADIUS|DIAMETER|THICKNESS(P).  {A = P}

// Properties with optional arguments
dashproperty(A) ::= DOTTED(A).
dashproperty(A) ::= DASHED(A).

// Color properties
colorproperty(A) ::= FILL(A).
colorproperty(A) ::= COLOR(A).

// Properties with no argument
boolproperty ::= CW.          {p.cur.cw = true}
boolproperty ::= CCW.         {p.cur.cw = false}
boolproperty ::= LARROW.      {p.cur.larrow=true; p.cur.rarrow=false }
boolproperty ::= RARROW.      {p.cur.larrow=false; p.cur.rarrow=true }
boolproperty ::= LRARROW.     {p.cur.larrow=true; p.cur.rarrow=true }
boolproperty ::= INVIS.       {p.cur.sw = -0.00001 }
boolproperty ::= THICK.       {p.cur.sw *= 1.5}
boolproperty ::= THIN.        {p.cur.sw *= 0.67}
boolproperty ::= SOLID.       {p.cur.sw = p.pik_value("thickness",nil)
                               p.cur.dotted = 0.0; p.cur.dashed = 0.0}

textposition(A) ::= .   {A = 0}
textposition(A) ::= textposition(B)
   CENTER|LJUST|RJUST|ABOVE|BELOW|ITALIC|BOLD|MONO|ALIGNED|BIG|SMALL(F).
                        {A = pik_text_position(B,&F)}


position(A) ::= expr(X) COMMA expr(Y).                {A.x=X; A.y=Y}
position(A) ::= place(A).
position(A) ::= place(B) PLUS expr(X) COMMA expr(Y).  {A.x=B.x+X; A.y=B.y+Y}
position(A) ::= place(B) MINUS expr(X) COMMA expr(Y). {A.x=B.x-X; A.y=B.y-Y}
position(A) ::= place(B) PLUS LP expr(X) COMMA expr(Y) RP.
                                                      {A.x=B.x+X; A.y=B.y+Y}
position(A) ::= place(B) MINUS LP expr(X) COMMA expr(Y) RP.
                                                      {A.x=B.x-X; A.y=B.y-Y}
position(A) ::= LP position(X) COMMA position(Y) RP.  {A.x=X.x; A.y=Y.y}
position(A) ::= LP position(X) RP.                    {A=X}
position(A) ::= expr(X) between position(P1) AND position(P2).
                                       {A = pik_position_between(X,P1,P2)}
position(A) ::= expr(X) LT position(P1) COMMA position(P2) GT.
                                       {A = pik_position_between(X,P1,P2)}
position(A) ::= expr(X) ABOVE position(B).    {A=B; A.y += X}
position(A) ::= expr(X) BELOW position(B).    {A=B; A.y -= X}
position(A) ::= expr(X) LEFT OF position(B).  {A=B; A.x -= X}
position(A) ::= expr(X) RIGHT OF position(B). {A=B; A.x += X}
position(A) ::= expr(D) ON HEADING EDGEPT(E) OF position(P).
                                        {A = pik_position_at_hdg(D,&E,P)}
position(A) ::= expr(D) HEADING EDGEPT(E) OF position(P).
                                        {A = pik_position_at_hdg(D,&E,P)}
position(A) ::= expr(D) EDGEPT(E) OF position(P).
                                        {A = pik_position_at_hdg(D,&E,P)}
position(A) ::= expr(D) ON HEADING expr(G) FROM position(P).
                                        {A = pik_position_at_angle(D,G,P)}
position(A) ::= expr(D) HEADING expr(G) FROM position(P).
                                        {A = pik_position_at_angle(D,G,P)}

between ::= WAY BETWEEN.
between ::= BETWEEN.
between ::= OF THE WAY BETWEEN.

// place2 is the same as place, but excludes the forms like
// "RIGHT of object" to avoid a parsing ambiguity with "place .x"
// and "place .y" expressions
%type place2 {PPoint}

place(A) ::= place2(A).
place(A) ::= edge(X) OF object(O).           {A = p.pik_place_of_elem(O,&X)}
place2(A) ::= object(O).                     {A = p.pik_place_of_elem(O,nil)}
place2(A) ::= object(O) DOT_E edge(X).       {A = p.pik_place_of_elem(O,&X)}
place2(A) ::= NTH(N) VERTEX(E) OF object(X). {A = p.pik_nth_vertex(&N,&E,X)}

edge(A) ::= CENTER(A).
edge(A) ::= EDGEPT(A).
edge(A) ::= TOP(A).
edge(A) ::= BOTTOM(A).
edge(A) ::= START(A).
edge(A) ::= END(A).
edge(A) ::= RIGHT(A).
edge(A) ::= LEFT(A).

object(A) ::= objectname(A).
object(A) ::= nth(N).                     {A = p.pik_find_nth(nil,&N)}
object(A) ::= nth(N) OF|IN object(B).     {A = p.pik_find_nth(B,&N)}

objectname(A) ::= THIS.                   {A = p.cur}
objectname(A) ::= PLACENAME(N).           {A = p.pik_find_byname(nil,&N)}
objectname(A) ::= objectname(B) DOT_U PLACENAME(N).
                                          {A = p.pik_find_byname(B,&N)}

nth(A) ::= NTH(N) CLASSNAME(ID).      {A=ID; A.eCode = p.pik_nth_value(&N) }
nth(A) ::= NTH(N) LAST CLASSNAME(ID). {A=ID; A.eCode = -p.pik_nth_value(&N) }
nth(A) ::= LAST CLASSNAME(ID).        {A=ID; A.eCode = -1}
nth(A) ::= LAST(ID).                  {A=ID; A.eCode = -1}
nth(A) ::= NTH(N) LB(ID) RB.          {A=ID; A.eCode = p.pik_nth_value(&N)}
nth(A) ::= NTH(N) LAST LB(ID) RB.     {A=ID; A.eCode = -p.pik_nth_value(&N)}
nth(A) ::= LAST LB(ID) RB.            {A=ID; A.eCode = -1 }

expr(A) ::= expr(X) PLUS expr(Y).                 {A=X+Y}
expr(A) ::= expr(X) MINUS expr(Y).                {A=X-Y}
expr(A) ::= expr(X) STAR expr(Y).                 {A=X*Y}
expr(A) ::= expr(X) SLASH(E) expr(Y).             {
  if Y==0.0 { p.pik_error(&E, "division by zero"); A = 0.0 } else{ A = X/Y }
}
expr(A) ::= MINUS expr(X). [UMINUS]               {A=-X}
expr(A) ::= PLUS expr(X). [UMINUS]                {A=X}
expr(A) ::= LP expr(X) RP.                        {A=X}
expr(A) ::= LP FILL|COLOR|THICKNESS(X) RP.        {A=p.pik_get_var(&X)}
expr(A) ::= NUMBER(N).                            {A=pik_atof(&N)}
expr(A) ::= ID(N).                                {A=p.pik_get_var(&N)}
expr(A) ::= FUNC1(F) LP expr(X) RP.               {A = p.pik_func(&F,X,0.0)}
expr(A) ::= FUNC2(F) LP expr(X) COMMA expr(Y) RP. {A = p.pik_func(&F,X,Y)}
expr(A) ::= DIST LP position(X) COMMA position(Y) RP. {A = pik_dist(&X,&Y)}
expr(A) ::= place2(B) DOT_XY X.                   {A = B.x}
expr(A) ::= place2(B) DOT_XY Y.                   {A = B.y}
expr(A) ::= object(B) DOT_L numproperty(P).       {A=pik_property_of(B,&P)}
expr(A) ::= object(B) DOT_L dashproperty(P).      {A=pik_property_of(B,&P)}
expr(A) ::= object(B) DOT_L colorproperty(P).     {A=pik_property_of(B,&P)}


%code {


/* Chart of the 148 official CSS color names with their
** corresponding RGB values thru Color Module Level 4:
** https://developer.mozilla.org/en-US/docs/Web/CSS/color_value
**
** Two new names "None" and "Off" are added with a value
** of -1.
*/
var aColor = []struct{
  zName string  /* Name of the color */
  val int       /* RGB value */
}{
  { "AliceBlue",                   0xf0f8ff },
  { "AntiqueWhite",                0xfaebd7 },
  { "Aqua",                        0x00ffff },
  { "Aquamarine",                  0x7fffd4 },
  { "Azure",                       0xf0ffff },
  { "Beige",                       0xf5f5dc },
  { "Bisque",                      0xffe4c4 },
  { "Black",                       0x000000 },
  { "BlanchedAlmond",              0xffebcd },
  { "Blue",                        0x0000ff },
  { "BlueViolet",                  0x8a2be2 },
  { "Brown",                       0xa52a2a },
  { "BurlyWood",                   0xdeb887 },
  { "CadetBlue",                   0x5f9ea0 },
  { "Chartreuse",                  0x7fff00 },
  { "Chocolate",                   0xd2691e },
  { "Coral",                       0xff7f50 },
  { "CornflowerBlue",              0x6495ed },
  { "Cornsilk",                    0xfff8dc },
  { "Crimson",                     0xdc143c },
  { "Cyan",                        0x00ffff },
  { "DarkBlue",                    0x00008b },
  { "DarkCyan",                    0x008b8b },
  { "DarkGoldenrod",               0xb8860b },
  { "DarkGray",                    0xa9a9a9 },
  { "DarkGreen",                   0x006400 },
  { "DarkGrey",                    0xa9a9a9 },
  { "DarkKhaki",                   0xbdb76b },
  { "DarkMagenta",                 0x8b008b },
  { "DarkOliveGreen",              0x556b2f },
  { "DarkOrange",                  0xff8c00 },
  { "DarkOrchid",                  0x9932cc },
  { "DarkRed",                     0x8b0000 },
  { "DarkSalmon",                  0xe9967a },
  { "DarkSeaGreen",                0x8fbc8f },
  { "DarkSlateBlue",               0x483d8b },
  { "DarkSlateGray",               0x2f4f4f },
  { "DarkSlateGrey",               0x2f4f4f },
  { "DarkTurquoise",               0x00ced1 },
  { "DarkViolet",                  0x9400d3 },
  { "DeepPink",                    0xff1493 },
  { "DeepSkyBlue",                 0x00bfff },
  { "DimGray",                     0x696969 },
  { "DimGrey",                     0x696969 },
  { "DodgerBlue",                  0x1e90ff },
  { "Firebrick",                   0xb22222 },
  { "FloralWhite",                 0xfffaf0 },
  { "ForestGreen",                 0x228b22 },
  { "Fuchsia",                     0xff00ff },
  { "Gainsboro",                   0xdcdcdc },
  { "GhostWhite",                  0xf8f8ff },
  { "Gold",                        0xffd700 },
  { "Goldenrod",                   0xdaa520 },
  { "Gray",                        0x808080 },
  { "Green",                       0x008000 },
  { "GreenYellow",                 0xadff2f },
  { "Grey",                        0x808080 },
  { "Honeydew",                    0xf0fff0 },
  { "HotPink",                     0xff69b4 },
  { "IndianRed",                   0xcd5c5c },
  { "Indigo",                      0x4b0082 },
  { "Ivory",                       0xfffff0 },
  { "Khaki",                       0xf0e68c },
  { "Lavender",                    0xe6e6fa },
  { "LavenderBlush",               0xfff0f5 },
  { "LawnGreen",                   0x7cfc00 },
  { "LemonChiffon",                0xfffacd },
  { "LightBlue",                   0xadd8e6 },
  { "LightCoral",                  0xf08080 },
  { "LightCyan",                   0xe0ffff },
  { "LightGoldenrodYellow",        0xfafad2 },
  { "LightGray",                   0xd3d3d3 },
  { "LightGreen",                  0x90ee90 },
  { "LightGrey",                   0xd3d3d3 },
  { "LightPink",                   0xffb6c1 },
  { "LightSalmon",                 0xffa07a },
  { "LightSeaGreen",               0x20b2aa },
  { "LightSkyBlue",                0x87cefa },
  { "LightSlateGray",              0x778899 },
  { "LightSlateGrey",              0x778899 },
  { "LightSteelBlue",              0xb0c4de },
  { "LightYellow",                 0xffffe0 },
  { "Lime",                        0x00ff00 },
  { "LimeGreen",                   0x32cd32 },
  { "Linen",                       0xfaf0e6 },
  { "Magenta",                     0xff00ff },
  { "Maroon",                      0x800000 },
  { "MediumAquamarine",            0x66cdaa },
  { "MediumBlue",                  0x0000cd },
  { "MediumOrchid",                0xba55d3 },
  { "MediumPurple",                0x9370db },
  { "MediumSeaGreen",              0x3cb371 },
  { "MediumSlateBlue",             0x7b68ee },
  { "MediumSpringGreen",           0x00fa9a },
  { "MediumTurquoise",             0x48d1cc },
  { "MediumVioletRed",             0xc71585 },
  { "MidnightBlue",                0x191970 },
  { "MintCream",                   0xf5fffa },
  { "MistyRose",                   0xffe4e1 },
  { "Moccasin",                    0xffe4b5 },
  { "NavajoWhite",                 0xffdead },
  { "Navy",                        0x000080 },
  { "None",                              -1 },  /* Non-standard addition */
  { "Off",                               -1 },  /* Non-standard addition */
  { "OldLace",                     0xfdf5e6 },
  { "Olive",                       0x808000 },
  { "OliveDrab",                   0x6b8e23 },
  { "Orange",                      0xffa500 },
  { "OrangeRed",                   0xff4500 },
  { "Orchid",                      0xda70d6 },
  { "PaleGoldenrod",               0xeee8aa },
  { "PaleGreen",                   0x98fb98 },
  { "PaleTurquoise",               0xafeeee },
  { "PaleVioletRed",               0xdb7093 },
  { "PapayaWhip",                  0xffefd5 },
  { "PeachPuff",                   0xffdab9 },
  { "Peru",                        0xcd853f },
  { "Pink",                        0xffc0cb },
  { "Plum",                        0xdda0dd },
  { "PowderBlue",                  0xb0e0e6 },
  { "Purple",                      0x800080 },
  { "RebeccaPurple",               0x663399 },
  { "Red",                         0xff0000 },
  { "RosyBrown",                   0xbc8f8f },
  { "RoyalBlue",                   0x4169e1 },
  { "SaddleBrown",                 0x8b4513 },
  { "Salmon",                      0xfa8072 },
  { "SandyBrown",                  0xf4a460 },
  { "SeaGreen",                    0x2e8b57 },
  { "Seashell",                    0xfff5ee },
  { "Sienna",                      0xa0522d },
  { "Silver",                      0xc0c0c0 },
  { "SkyBlue",                     0x87ceeb },
  { "SlateBlue",                   0x6a5acd },
  { "SlateGray",                   0x708090 },
  { "SlateGrey",                   0x708090 },
  { "Snow",                        0xfffafa },
  { "SpringGreen",                 0x00ff7f },
  { "SteelBlue",                   0x4682b4 },
  { "Tan",                         0xd2b48c },
  { "Teal",                        0x008080 },
  { "Thistle",                     0xd8bfd8 },
  { "Tomato",                      0xff6347 },
  { "Turquoise",                   0x40e0d0 },
  { "Violet",                      0xee82ee },
  { "Wheat",                       0xf5deb3 },
  { "White",                       0xffffff },
  { "WhiteSmoke",                  0xf5f5f5 },
  { "Yellow",                      0xffff00 },
  { "YellowGreen",                 0x9acd32 },
}

/* Built-in variable names.
**
** This array is constant.  When a script changes the value of one of
** these built-ins, a new PVar record is added at the head of
** the Pik.pVar list, which is searched first.  Thus the new PVar entry
** will override this default value.
**
** Units are in inches, except for "color" and "fill" which are
** interpreted as 24-bit RGB values.
**
** Binary search used.  Must be kept in sorted order.
*/

var aBuiltin = []struct{
  zName string
  val   PNum
}{
  { "arcrad",      0.25  },
  { "arrowhead",   2.0   },
  { "arrowht",     0.08  },
  { "arrowwid",    0.06  },
  { "boxht",       0.5   },
  { "boxrad",      0.0   },
  { "boxwid",      0.75  },
  { "charht",      0.14  },
  { "charwid",     0.08  },
  { "circlerad",   0.25  },
  { "color",       0.0   },
  { "cylht",       0.5   },
  { "cylrad",      0.075 },
  { "cylwid",      0.75  },
  { "dashwid",     0.05  },
  { "diamondht",   0.75  },
  { "diamondwid",  1.0   },
  { "dotrad",      0.015 },
  { "ellipseht",   0.5   },
  { "ellipsewid",  0.75  },
  { "fileht",      0.75  },
  { "filerad",     0.15  },
  { "filewid",     0.5   },
  { "fill",        -1.0  },
  { "lineht",      0.5   },
  { "linewid",     0.5   },
  { "movewid",     0.5   },
  { "ovalht",      0.5   },
  { "ovalwid",     1.0   },
  { "scale",       1.0   },
  { "textht",      0.5   },
  { "textwid",     0.75  },
  { "thickness",   0.015 },
}


/* Methods for the "arc" class */
func arcInit(p *Pik, pObj *PObj) {
  pObj.w = p.pik_value("arcrad",nil)
  pObj.h = pObj.w
}

/* Hack: Arcs are here rendered as quadratic Bezier curves rather
** than true arcs.  Multiple reasons: (1) the legacy-PIC parameters
** that control arcs are obscure and I could not figure out what they
** mean based on available documentation.  (2) Arcs are rarely used,
** and so do not seem that important.
*/
func arcControlPoint(cw bool, f PPoint, t PPoint, rScale PNum) PPoint {
  var m PPoint
  var dx, dy PNum
  m.x = 0.5*(f.x+t.x)
  m.y = 0.5*(f.y+t.y)
  dx = t.x - f.x
  dy = t.y - f.y
  if cw {
    m.x -= 0.5*rScale*dy
    m.y += 0.5*rScale*dx
  }else{
    m.x += 0.5*rScale*dy
    m.y -= 0.5*rScale*dx
  }
  return m
}
func arcCheck(p *Pik, pObj *PObj) {
  if p.nTPath>2 {
    p.pik_error(&pObj.errTok, "arc geometry error")
    return
  }
  m := arcControlPoint(pObj.cw, p.aTPath[0], p.aTPath[1], 0.5)
  pik_bbox_add_xy(&pObj.bbox, m.x, m.y)
}
func arcRender(p *Pik, pObj *PObj) {
  if pObj.nPath<2 { return }
  if pObj.sw<0.0 { return }
  f := pObj.aPath[0]
  t := pObj.aPath[1]
  m := arcControlPoint(pObj.cw,f,t,1.0)
  if pObj.larrow {
    p.pik_draw_arrowhead(&m,&f,pObj)
  }
  if pObj.rarrow {
    p.pik_draw_arrowhead(&m,&t,pObj)
  }
  p.pik_append_xy("<path d=\"M", f.x, f.y)
  p.pik_append_xy("Q", m.x, m.y)
  p.pik_append_xy(" ", t.x, t.y)
  p.pik_append("\" ")
  p.pik_append_style(pObj,0)
  p.pik_append("\" />\n")

  p.pik_append_txt(pObj, nil)
}


/* Methods for the "arrow" class */
func arrowInit(p *Pik, pObj *PObj) {
  pObj.w = p.pik_value("linewid",nil)
  pObj.h = p.pik_value("lineht",nil)
  pObj.rad = p.pik_value("linerad",nil)
  pObj.rarrow = true
}

/* Methods for the "box" class */
func boxInit(p *Pik, pObj *PObj) {
  pObj.w = p.pik_value("boxwid",nil)
  pObj.h = p.pik_value("boxht",nil)
  pObj.rad = p.pik_value("boxrad",nil)
}
/* Return offset from the center of the box to the compass point
** given by parameter cp */
func boxOffset(p *Pik, pObj *PObj, cp uint8) PPoint {
  pt := PPoint{}
  var w2 PNum = 0.5*pObj.w
  var h2 PNum = 0.5*pObj.h
  var rad PNum = pObj.rad
  var rx PNum
  if rad<=0.0 {
    rx = 0.0
  }else{
    if rad>w2 { rad = w2 }
    if rad>h2 { rad = h2 }
    rx = 0.29289321881345252392*rad
  }
  switch cp {
    case CP_C:
    case CP_N:   pt.x = 0.0;      pt.y = h2
    case CP_NE:  pt.x = w2-rx;    pt.y = h2-rx
    case CP_E:   pt.x = w2;       pt.y = 0.0
    case CP_SE:  pt.x = w2-rx;    pt.y = rx-h2
    case CP_S:   pt.x = 0.0;      pt.y = -h2
    case CP_SW:  pt.x = rx-w2;    pt.y = rx-h2
    case CP_W:   pt.x = -w2;      pt.y = 0.0
    case CP_NW:  pt.x = rx-w2;    pt.y = h2-rx
    default:     assert(false, "false")
  }
  return pt
}
func boxChop(p *Pik, pObj *PObj, pPt *PPoint) PPoint {
  var dx, dy PNum
  cp := CP_C
  chop := pObj.ptAt
  if pObj.w<=0.0 { return chop }
  if pObj.h<=0.0 { return chop }
  dx = (pPt.x - pObj.ptAt.x)*pObj.h/pObj.w
  dy = (pPt.y - pObj.ptAt.y)
  if dx>0.0 {
    if dy>=2.414*dx {
      cp = CP_N
    } else if dy>=0.414*dx {
      cp = CP_NE
    } else if dy>=-0.414*dx {
      cp = CP_E
    } else if dy>-2.414*dx {
      cp = CP_SE
    } else {
      cp = CP_S
    }
  } else {
    if dy>=-2.414*dx {
      cp = CP_N
    } else if dy>=-0.414*dx {
      cp = CP_NW
    } else if dy>=0.414*dx {
      cp = CP_W
    } else if dy>2.414*dx {
      cp = CP_SW
    } else {
      cp = CP_S
    }
  }
  chop = pObj.typ.xOffset(p,pObj,cp)
  chop.x += pObj.ptAt.x
  chop.y += pObj.ptAt.y
  return chop
}
func boxFit(p *Pik, pObj *PObj, w PNum, h PNum) {
  if w>0 { pObj.w = w }
  if h>0 { pObj.h = h }
}
func boxRender(p *Pik, pObj *PObj) {
  var w2 PNum = 0.5*pObj.w
  var h2 PNum = 0.5*pObj.h
  rad := pObj.rad
  pt := pObj.ptAt
  if pObj.sw>=0.0 {
    if rad<=0.0 {
      p.pik_append_xy("<path d=\"M", pt.x-w2,pt.y-h2)
      p.pik_append_xy("L", pt.x+w2,pt.y-h2)
      p.pik_append_xy("L", pt.x+w2,pt.y+h2)
      p.pik_append_xy("L", pt.x-w2,pt.y+h2)
      p.pik_append("Z\" ")
    } else {
      /*
      **         ----       - y3
      **        /    \
      **       /      \     _ y2
      **      |        |
      **      |        |    _ y1
      **       \      /
      **        \    /
      **         ----       _ y0
      **
      **      '  '  '  '
      **     x0 x1 x2 x3
      */
      if rad>w2 { rad = w2 }
      if rad>h2 { rad = h2 }
      var x0 PNum = pt.x - w2
      var x1 PNum = x0 + rad
      var x3 PNum = pt.x + w2
      var x2 PNum = x3 - rad
      var y0 PNum = pt.y - h2
      var y1 PNum = y0 + rad
      var y3 PNum = pt.y + h2
      var y2 PNum = y3 - rad
      p.pik_append_xy("<path d=\"M", x1, y0)
      if x2>x1 { p.pik_append_xy("L", x2, y0) }
      p.pik_append_arc(rad, rad, x3, y1)
      if y2>y1 { p.pik_append_xy("L", x3, y2) }
      p.pik_append_arc(rad, rad, x2, y3)
      if x2>x1 { p.pik_append_xy("L", x1, y3) }
      p.pik_append_arc(rad, rad, x0, y2)
      if y2>y1 { p.pik_append_xy("L", x0, y1) }
      p.pik_append_arc(rad, rad, x1, y0)
      p.pik_append("Z\" ")
    }
    p.pik_append_style(pObj,3)
    p.pik_append("\" />\n")
  }
  p.pik_append_txt(pObj, nil)
}

/* Methods for the "circle" class */
func circleInit(p *Pik, pObj *PObj) {
  pObj.w = p.pik_value("circlerad",nil)*2
  pObj.h = pObj.w
  pObj.rad = 0.5*pObj.w
}
func circleNumProp(p *Pik, pObj *PObj, pId *PToken) {
  /* For a circle, the width must equal the height and both must
  ** be twice the radius.  Enforce those constraints. */
  switch pId.eType {
  case T_DIAMETER, T_RADIUS:
    pObj.w = 2.0*pObj.rad
    pObj.h = 2.0*pObj.rad
  case T_WIDTH:
    pObj.h = pObj.w
    pObj.rad = 0.5*pObj.w
  case T_HEIGHT:
    pObj.w = pObj.h
    pObj.rad = 0.5*pObj.w
  }
}
func circleChop(p *Pik, pObj *PObj, pPt *PPoint) PPoint {
  var chop PPoint
   var dx PNum = pPt.x - pObj.ptAt.x
   var dy PNum = pPt.y - pObj.ptAt.y
   var dist PNum= math.Hypot(dx,dy)
  if dist<pObj.rad || dist<=0 { return pObj.ptAt }
  chop.x = pObj.ptAt.x + dx*pObj.rad/dist
  chop.y = pObj.ptAt.y + dy*pObj.rad/dist
  return chop
}
func circleFit(p *Pik, pObj *PObj, w PNum, h PNum) {
  var mx PNum = 0.0
  if w>0 { mx = w }
  if h>mx { mx = h }
  if w*h>0 && (w*w + h*h) > mx*mx {
    mx = math.Hypot(w,h)
  }
  if mx>0.0 {
    pObj.rad = 0.5*mx
    pObj.w = mx
    pObj.h = mx
  }
}

func circleRender(p *Pik, pObj *PObj) {
  r := pObj.rad
  pt := pObj.ptAt
  if pObj.sw>=0.0 {
    p.pik_append_x("<circle cx=\"", pt.x, "\"")
    p.pik_append_y(" cy=\"", pt.y, "\"")
    p.pik_append_dis(" r=\"", r, "\" ")
    p.pik_append_style(pObj,3)
    p.pik_append("\" />\n")
  }
  p.pik_append_txt(pObj, nil)
}

/* Methods for the "cylinder" class */
func cylinderInit(p *Pik, pObj *PObj) {
  pObj.w = p.pik_value("cylwid",nil)
  pObj.h = p.pik_value("cylht",nil)
  pObj.rad = p.pik_value("cylrad",nil) /* Minor radius of ellipses */
}
func cylinderFit(p *Pik, pObj *PObj, w PNum, h PNum) {
  if w>0 { pObj.w = w }
  if h>0 { pObj.h = h + 0.25*pObj.rad + pObj.sw }
}
func cylinderRender(p *Pik, pObj *PObj) {
  var w2 PNum = 0.5*pObj.w
  var h2 PNum = 0.5*pObj.h
  rad := pObj.rad
  pt := pObj.ptAt
  if pObj.sw>=0.0 {
    if rad>h2 {
      rad = h2
    }else if rad<0 {
      rad = 0
    }
    p.pik_append_xy("<path d=\"M", pt.x-w2,pt.y+h2-rad)
    p.pik_append_xy("L", pt.x-w2,pt.y-h2+rad)
    p.pik_append_arc(w2,rad,pt.x+w2,pt.y-h2+rad)
    p.pik_append_xy("L", pt.x+w2,pt.y+h2-rad)
    p.pik_append_arc(w2,rad,pt.x-w2,pt.y+h2-rad)
    p.pik_append_arc(w2,rad,pt.x+w2,pt.y+h2-rad)
    p.pik_append("\" ")
    p.pik_append_style(pObj,3)
    p.pik_append("\" />\n")
  }
  p.pik_append_txt(pObj, nil)
}
func cylinderOffset(p *Pik, pObj *PObj, cp uint8) PPoint {
  pt := PPoint{}
  var w2 PNum = pObj.w*0.5
  var h1 PNum = pObj.h*0.5
  var h2 PNum = h1 - pObj.rad
  switch cp {
    case CP_C:
    case CP_N:   pt.x = 0.0;   pt.y = h1
    case CP_NE:  pt.x = w2;    pt.y = h2
    case CP_E:   pt.x = w2;    pt.y = 0.0
    case CP_SE:  pt.x = w2;    pt.y = -h2
    case CP_S:   pt.x = 0.0;   pt.y = -h1
    case CP_SW:  pt.x = -w2;   pt.y = -h2
    case CP_W:   pt.x = -w2;   pt.y = 0.0
    case CP_NW:  pt.x = -w2;   pt.y = h2
    default:     assert(false, "false")
  }
  return pt
}

/* Methods for the "dot" class */
func dotInit(p *Pik, pObj *PObj) {
  pObj.rad = p.pik_value("dotrad",nil)
  pObj.h = pObj.rad*6
  pObj.w = pObj.rad*6
  pObj.fill = pObj.color
}
func dotNumProp(p *Pik, pObj *PObj, pId *PToken) {
  switch pId.eType {
    case T_COLOR:
      pObj.fill = pObj.color
    case T_FILL:
      pObj.color = pObj.fill
  }
}
func dotCheck(p *Pik, pObj *PObj){
  pObj.w = 0
  pObj.h = 0
  pik_bbox_addellipse(&pObj.bbox, pObj.ptAt.x, pObj.ptAt.y,
                       pObj.rad, pObj.rad)
}
func dotOffset(p *Pik, pObj *PObj, cp uint8) PPoint {
  return PPoint{}
}
func dotRender(p *Pik, pObj *PObj){
  r := pObj.rad
  pt := pObj.ptAt
  if pObj.sw>=0.0 {
    p.pik_append_x("<circle cx=\"", pt.x, "\"")
    p.pik_append_y(" cy=\"", pt.y, "\"")
    p.pik_append_dis(" r=\"", r, "\"")
    p.pik_append_style(pObj,2)
    p.pik_append("\" />\n")
  }
  p.pik_append_txt(pObj, nil)
}

/* Methods for the "diamond" class */
func diamondInit(p *Pik, pObj *PObj){
  pObj.w = p.pik_value("diamondwid",nil)
  pObj.h = p.pik_value("diamondht",nil)
  pObj.bAltAutoFit = true
}
/* Return offset from the center of the box to the compass point
** given by parameter cp */
func diamondOffset(p *Pik, pObj *PObj, cp uint8) PPoint {
  var pt PPoint
  var w2 PNum = 0.5*pObj.w
  var w4 PNum = 0.25*pObj.w
  var h2 PNum = 0.5*pObj.h
  var h4 PNum = 0.25*pObj.h
  switch( cp ){
    case CP_C:
    case CP_N:   pt.x = 0.0;      pt.y = h2
    case CP_NE:  pt.x = w4;       pt.y = h4
    case CP_E:   pt.x = w2;       pt.y = 0.0
    case CP_SE:  pt.x = w4;       pt.y = -h4
    case CP_S:   pt.x = 0.0;      pt.y = -h2
    case CP_SW:  pt.x = -w4;      pt.y = -h4
    case CP_W:   pt.x = -w2;      pt.y = 0.0
    case CP_NW:  pt.x = -w4;      pt.y = h4
    default:     assert(false, "false")
  }
  return pt
}
func diamondFit(p *Pik, pObj *PObj, w PNum, h PNum){
  if pObj.w<=0 { pObj.w = w*1.5 }
  if pObj.h<=0 { pObj.h = h*1.5 }
  if pObj.w>0 && pObj.h>0 {
    var x PNum = pObj.w*h/pObj.h + w
    var y PNum = pObj.h*x/pObj.w
    pObj.w = x
    pObj.h = y
  }
}
func diamondRender(p *Pik, pObj *PObj){
  var w2 PNum = 0.5*pObj.w
  var h2 PNum = 0.5*pObj.h
  pt := pObj.ptAt
  if pObj.sw>=0.0 {
    p.pik_append_xy("<path d=\"M", pt.x-w2,pt.y)
    p.pik_append_xy("L", pt.x,pt.y-h2)
    p.pik_append_xy("L", pt.x+w2,pt.y)
    p.pik_append_xy("L", pt.x,pt.y+h2)
    p.pik_append("Z\" ");
    p.pik_append_style(pObj,3);
    p.pik_append("\" />\n");
  }
  p.pik_append_txt(pObj, nil);
}

/* Methods for the "ellipse" class */
func ellipseInit(p *Pik, pObj *PObj){
  pObj.w = p.pik_value("ellipsewid",nil)
  pObj.h = p.pik_value("ellipseht",nil)
}
func ellipseChop(p *Pik, pObj *PObj, pPt *PPoint) PPoint {
  var chop PPoint
  var s, dq, dist PNum
  var dx PNum = pPt.x - pObj.ptAt.x
  var dy PNum = pPt.y - pObj.ptAt.y
  if pObj.w<=0.0 { return pObj.ptAt }
  if pObj.h<=0.0 { return pObj.ptAt }
  s = pObj.h/pObj.w
  dq = dx*s
  dist = math.Hypot(dq,dy)
  if dist<pObj.h { return pObj.ptAt }
  chop.x = pObj.ptAt.x + 0.5*dq*pObj.h/(dist*s)
  chop.y = pObj.ptAt.y + 0.5*dy*pObj.h/dist
  return chop
}
func ellipseOffset(p *Pik, pObj *PObj, cp uint8) PPoint {
  pt := PPoint{}
  var w PNum = pObj.w*0.5
  var w2 PNum = w*0.70710678118654747608
  var h PNum = pObj.h*0.5
  var h2 PNum = h*0.70710678118654747608
  switch cp {
    case CP_C:
    case CP_N:   pt.x = 0.0;   pt.y = h
    case CP_NE:  pt.x = w2;    pt.y = h2
    case CP_E:   pt.x = w;     pt.y = 0.0
    case CP_SE:  pt.x = w2;    pt.y = -h2
    case CP_S:   pt.x = 0.0;   pt.y = -h
    case CP_SW:  pt.x = -w2;   pt.y = -h2
    case CP_W:   pt.x = -w;    pt.y = 0.0
    case CP_NW:  pt.x = -w2;   pt.y = h2
    default:     assert(false, "false")
  }
  return pt
}
func ellipseRender(p *Pik, pObj *PObj){
  w := pObj.w
  h := pObj.h
  pt := pObj.ptAt
  if pObj.sw>=0.0 {
    p.pik_append_x("<ellipse cx=\"", pt.x, "\"")
    p.pik_append_y(" cy=\"", pt.y, "\"")
    p.pik_append_dis(" rx=\"", w/2.0, "\"")
    p.pik_append_dis(" ry=\"", h/2.0, "\" ")
    p.pik_append_style(pObj,3)
    p.pik_append("\" />\n")
  }
  p.pik_append_txt(pObj, nil)
}

/* Methods for the "file" object */
func fileInit(p *Pik, pObj *PObj){
  pObj.w = p.pik_value("filewid",nil)
  pObj.h = p.pik_value("fileht",nil)
  pObj.rad = p.pik_value("filerad",nil)
}
/* Return offset from the center of the file to the compass point
** given by parameter cp */
func fileOffset(p *Pik, pObj *PObj, cp uint8) PPoint {
  pt := PPoint{}
  var w2 PNum = 0.5*pObj.w
  var h2 PNum = 0.5*pObj.h
  var rx PNum = pObj.rad
  mn := h2
  if w2<h2 {mn = w2}
  if rx>mn { rx = mn }
  if rx<mn*0.25 { rx = mn*0.25 }
  pt.x = 0.0
  pt.y = 0.0
  rx *= 0.5
  switch cp {
    case CP_C:
    case CP_N:   pt.x = 0.0;      pt.y = h2
    case CP_NE:  pt.x = w2-rx;    pt.y = h2-rx
    case CP_E:   pt.x = w2;       pt.y = 0.0
    case CP_SE:  pt.x = w2;       pt.y = -h2
    case CP_S:   pt.x = 0.0;      pt.y = -h2
    case CP_SW:  pt.x = -w2;      pt.y = -h2
    case CP_W:   pt.x = -w2;      pt.y = 0.0
    case CP_NW:  pt.x = -w2;      pt.y = h2
    default:     assert(false, "false")
  }
  return pt
}
func fileFit(p *Pik, pObj *PObj, w PNum, h PNum){
  if w>0 { pObj.w = w }
  if h>0 { pObj.h = h + 2*pObj.rad }
}
func fileRender(p *Pik, pObj *PObj){
  var w2 PNum = 0.5*pObj.w
  var h2 PNum = 0.5*pObj.h
  rad := pObj.rad
  pt := pObj.ptAt
  mn := h2
  if w2<h2 { mn = w2 }
  if rad>mn { rad = mn }
  if rad<mn*0.25 { rad = mn*0.25 }
  if pObj.sw>=0.0 {
    p.pik_append_xy("<path d=\"M", pt.x-w2,pt.y-h2)
    p.pik_append_xy("L", pt.x+w2,pt.y-h2)
    p.pik_append_xy("L", pt.x+w2,pt.y+(h2-rad))
    p.pik_append_xy("L", pt.x+(w2-rad),pt.y+h2)
    p.pik_append_xy("L", pt.x-w2,pt.y+h2)
    p.pik_append("Z\" ")
    p.pik_append_style(pObj,1)
    p.pik_append("\" />\n")
    p.pik_append_xy("<path d=\"M", pt.x+(w2-rad), pt.y+h2)
    p.pik_append_xy("L", pt.x+(w2-rad),pt.y+(h2-rad))
    p.pik_append_xy("L", pt.x+w2, pt.y+(h2-rad))
    p.pik_append("\" ")
    p.pik_append_style(pObj,0)
    p.pik_append("\" />\n")
  }
  p.pik_append_txt(pObj, nil)
}


/* Methods for the "line" class */
func lineInit(p *Pik, pObj *PObj){
  pObj.w = p.pik_value("linewid",nil)
  pObj.h = p.pik_value("lineht",nil)
  pObj.rad = p.pik_value("linerad",nil)
}
func lineOffset(p *Pik, pObj *PObj, cp uint8) PPoint {
  if false { // #if 0
    /* In legacy PIC, the .center of an unclosed line is half way between
     ** its .start and .end. */
    if cp==CP_C && !pObj.bClose {
      var out PPoint
      out.x = 0.5*(pObj.ptEnter.x + pObj.ptExit.x) - pObj.ptAt.x
      out.y = 0.5*(pObj.ptEnter.x + pObj.ptExit.y) - pObj.ptAt.y
      return out
    }
  } // #endif
  return boxOffset(p,pObj,cp)
}
func lineRender(p *Pik, pObj *PObj){
  if pObj.sw>0.0 {
    z := "<path d=\"M"
    n := pObj.nPath
    if pObj.larrow {
      p.pik_draw_arrowhead(&pObj.aPath[1],&pObj.aPath[0],pObj)
    }
    if pObj.rarrow {
      p.pik_draw_arrowhead(&pObj.aPath[n-2],&pObj.aPath[n-1],pObj)
    }
    for i:=0; i<pObj.nPath; i++ {
      p.pik_append_xy(z,pObj.aPath[i].x,pObj.aPath[i].y)
      z = "L"
    }
    if pObj.bClose {
      p.pik_append("Z")
    } else {
      pObj.fill = -1.0
    }
    p.pik_append("\" ")
    if pObj.bClose {
      p.pik_append_style(pObj,3)
    } else {
      p.pik_append_style(pObj,0)
    }
    p.pik_append("\" />\n")
  }
  p.pik_append_txt(pObj, nil)
}

/* Methods for the "move" class */
func moveInit(p *Pik, pObj *PObj){
  pObj.w = p.pik_value("movewid",nil)
  pObj.h = pObj.w
  pObj.fill = -1.0
  pObj.color = -1.0
  pObj.sw = -1.0
}
func moveRender(p *Pik, pObj *PObj){
  /* No-op */
}

/* Methods for the "oval" class */
func ovalInit(p *Pik, pObj *PObj){
  pObj.h = p.pik_value("ovalht",nil)
  pObj.w = p.pik_value("ovalwid",nil)
  if pObj.h<pObj.w {
    pObj.rad = 0.5*pObj.h
  } else {
    pObj.rad = 0.5*pObj.w
  }
}
func ovalNumProp(p *Pik, pObj *PObj, pId *PToken){
  /* Always adjust the radius to be half of the smaller of
  ** the width and height. */
  if pObj.h<pObj.w {
    pObj.rad = 0.5*pObj.h
  } else {
    pObj.rad = 0.5*pObj.w
  }
}
func ovalFit(p *Pik, pObj *PObj, w PNum, h PNum){
  if w>0 { pObj.w = w }
  if h>0 { pObj.h = h }
  if pObj.w<pObj.h { pObj.w = pObj.h }
  if pObj.h<pObj.w {
    pObj.rad = 0.5*pObj.h
  } else {
    pObj.rad = 0.5*pObj.w
  }
}



/* Methods for the "spline" class */
func splineInit(p *Pik, pObj *PObj){
  pObj.w = p.pik_value("linewid",nil)
  pObj.h = p.pik_value("lineht",nil)
  pObj.rad = 1000
}
/* Return a point along the path from "f" to "t" that is r units
** prior to reaching "t", except if the path is less than 2*r total,
** return the midpoint.
*/
func radiusMidpoint(f PPoint, t PPoint, r PNum, pbMid *bool) PPoint {
  var dx PNum = t.x - f.x
  var dy PNum = t.y - f.y
  var dist PNum = math.Hypot(dx,dy)
  if dist<=0.0 { return t }
  dx /= dist
  dy /= dist
  if r > 0.5*dist {
    r = 0.5*dist
    *pbMid = true
  }else{
    *pbMid = false
  }
  return PPoint{
    x:  t.x - r*dx,
    y: t.y - r*dy,
  }
}
func (p *Pik) radiusPath(pObj *PObj, r PNum){
  n := pObj.nPath
  a := pObj.aPath
  an := a[n-1]
  isMid := false
  iLast := n-1
  if pObj.bClose {
    iLast = n
  }

  p.pik_append_xy("<path d=\"M", a[0].x, a[0].y)
  m := radiusMidpoint(a[0], a[1], r, &isMid)
  p.pik_append_xy(" L ",m.x,m.y)
  for i:=1; i<iLast; i++ {
    an = a[0]
    if i<n-1 { an = a[i+1]}
    m = radiusMidpoint(an,a[i],r, &isMid)
    p.pik_append_xy(" Q ",a[i].x,a[i].y)
    p.pik_append_xy(" ",m.x,m.y)
    if !isMid {
      m = radiusMidpoint(a[i],an,r, &isMid)
      p.pik_append_xy(" L ",m.x,m.y)
    }
  }
  p.pik_append_xy(" L ",an.x,an.y)
  if pObj.bClose {
    p.pik_append("Z")
  } else {
    pObj.fill = -1.0
  }
  p.pik_append("\" ")
  if pObj.bClose {
    p.pik_append_style(pObj,3)
  } else {
    p.pik_append_style(pObj,0)
  }
  p.pik_append("\" />\n")
}
func splineRender(p *Pik, pObj *PObj){
  if pObj.sw>0.0 {
    n := pObj.nPath
    r := pObj.rad
    if n<3 || r<=0.0 {
      lineRender(p,pObj)
      return
    }
    if pObj.larrow {
      p.pik_draw_arrowhead(&pObj.aPath[1],&pObj.aPath[0],pObj)
    }
    if pObj.rarrow {
      p.pik_draw_arrowhead(&pObj.aPath[n-2],&pObj.aPath[n-1],pObj)
    }
    p.radiusPath(pObj,pObj.rad)
  }
  p.pik_append_txt(pObj, nil)
}


/* Methods for the "text" class */
func textInit(p *Pik, pObj *PObj){
  p.pik_value("textwid",nil)
  p.pik_value("textht",nil)
  pObj.sw = 0.0
}
func textOffset(p *Pik, pObj *PObj, cp uint8) PPoint {
  /* Automatically slim-down the width and height of text
  ** statements so that the bounding box tightly encloses the text,
  ** then get boxOffset() to do the offset computation.
  */
  p.pik_size_to_fit(pObj, &pObj.errTok,3)
  return boxOffset(p, pObj, cp)
}

func textRender(p *Pik, pObj *PObj){
  p.pik_append_txt(pObj, nil)
}

/* Methods for the "sublist" class */
func sublistInit(p *Pik, pObj *PObj){
  pList := pObj.pSublist
  pik_bbox_init(&pObj.bbox)
  for i:=0; i<len(pList); i++ {
    pik_bbox_addbox(&pObj.bbox, &pList[i].bbox)
  }
  pObj.w = pObj.bbox.ne.x - pObj.bbox.sw.x
  pObj.h = pObj.bbox.ne.y - pObj.bbox.sw.y
  pObj.ptAt.x = 0.5*(pObj.bbox.ne.x + pObj.bbox.sw.x)
  pObj.ptAt.y = 0.5*(pObj.bbox.ne.y + pObj.bbox.sw.y)
  pObj.mCalc |= A_WIDTH|A_HEIGHT|A_RADIUS
}

/*
** The following array holds all the different kinds of objects.
** The special [] object is separate.
*/
var aClass = []PClass{
   {
      zName:          "arc",
      isLine:        true,
      eJust:         0,
      xInit:         arcInit,
      xNumProp:      nil,
      xCheck:        arcCheck,
      xChop:         nil,
      xOffset:       boxOffset,
      xFit:          nil,
      xRender:       arcRender,
   },
   {
      zName:          "arrow",
      isLine:        true,
      eJust:         0,
      xInit:         arrowInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         nil,
      xOffset:       lineOffset,
      xFit:          nil,
      xRender:       splineRender,
   },
   {
      zName:          "box",
      isLine:        false,
      eJust:         1,
      xInit:         boxInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         boxChop,
      xOffset:       boxOffset,
      xFit:          boxFit,
      xRender:       boxRender,
   },
   {
      zName:          "circle",
      isLine:        false,
      eJust:         0,
      xInit:         circleInit,
      xNumProp:      circleNumProp,
      xCheck:        nil,
      xChop:         circleChop,
      xOffset:       ellipseOffset,
      xFit:          circleFit,
      xRender:       circleRender,
   },
   {
      zName:          "cylinder",
      isLine:        false,
      eJust:         1,
      xInit:         cylinderInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         boxChop,
      xOffset:       cylinderOffset,
      xFit:          cylinderFit,
      xRender:       cylinderRender,
   },
   {
      zName:          "diamond",
      isLine:        false,
      eJust:         0,
      xInit:         diamondInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         boxChop,
      xOffset:       diamondOffset,
      xFit:          diamondFit,
      xRender:       diamondRender,
   },
   {
      zName:          "dot",
      isLine:        false,
      eJust:         0,
      xInit:         dotInit,
      xNumProp:      dotNumProp,
      xCheck:        dotCheck,
      xChop:         circleChop,
      xOffset:       dotOffset,
      xFit:          nil,
      xRender:       dotRender,
   },
   {
      zName:          "ellipse",
      isLine:        false,
      eJust:         0,
      xInit:         ellipseInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         ellipseChop,
      xOffset:       ellipseOffset,
      xFit:          boxFit,
      xRender:       ellipseRender,
   },
   {
      zName:          "file",
      isLine:        false,
      eJust:         1,
      xInit:         fileInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         boxChop,
      xOffset:       fileOffset,
      xFit:          fileFit,
      xRender:       fileRender,
   },
   {
      zName:          "line",
      isLine:        true,
      eJust:         0,
      xInit:         lineInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         nil,
      xOffset:       lineOffset,
      xFit:          nil,
      xRender:       splineRender,
   },
   {
      zName:          "move",
      isLine:        true,
      eJust:         0,
      xInit:         moveInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         nil,
      xOffset:       boxOffset,
      xFit:          nil,
      xRender:       moveRender,
   },
   {
      zName:          "oval",
      isLine:        false,
      eJust:         1,
      xInit:         ovalInit,
      xNumProp:      ovalNumProp,
      xCheck:        nil,
      xChop:         boxChop,
      xOffset:       boxOffset,
      xFit:          ovalFit,
      xRender:       boxRender,
   },
   {
      zName:          "spline",
      isLine:        true,
      eJust:         0,
      xInit:         splineInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         nil,
      xOffset:       lineOffset,
      xFit:          nil,
      xRender:       splineRender,
   },
   {
      zName:          "text",
      isLine:        false,
      eJust:         0,
      xInit:         textInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         boxChop,
      xOffset:       textOffset,
      xFit:          boxFit,
      xRender:       textRender,
   },
}
var sublistClass = PClass{
      zName:          "[]",
      isLine:        false,
      eJust:         0,
      xInit:         sublistInit,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         nil,
      xOffset:       boxOffset,
      xFit:          nil,
      xRender:       nil,
}
var noopClass =  PClass{
      zName:          "noop",
      isLine:        false,
      eJust:         0,
      xInit:         nil,
      xNumProp:      nil,
      xCheck:        nil,
      xChop:         nil,
      xOffset:       boxOffset,
      xFit:          nil,
      xRender:       nil,
}

/*
** Reduce the length of the line segment by amt (if possible) by
** modifying the location of *t.
*/
func pik_chop(f *PPoint, t *PPoint, amt PNum) {
  var dx PNum = t.x - f.x
  var dy PNum = t.y - f.y
  var dist PNum = math.Hypot(dx,dy)
  if dist<=amt {
    *t = *f
    return
  }
  var r PNum = 1.0 - amt/dist
  t.x = f.x + r*dx
  t.y = f.y + r*dy
}

/*
** Draw an arrowhead on the end of the line segment from pFrom to pTo.
** Also, shorten the line segment (by changing the value of pTo) so that
** the shaft of the arrow does not extend into the arrowhead.
*/
func (p *Pik) pik_draw_arrowhead(f *PPoint, t *PPoint, pObj *PObj) {
  var dx PNum = t.x - f.x
  var dy PNum = t.y - f.y
  var dist PNum = math.Hypot(dx,dy)
  var h PNum = p.hArrow * pObj.sw
  var w PNum = p.wArrow * pObj.sw
  if pObj.color<0.0 { return }
  if pObj.sw<=0.0 { return }
  if dist<=0.0 { return }  /* Unable */
  dx /= dist
  dy /= dist
  var e1 PNum = dist - h
  if e1<0.0 {
    e1 = 0.0
    h = dist
  }
  var ddx PNum = -w*dy
  var ddy PNum = w*dx
  var bx PNum = f.x + e1*dx
  var by PNum = f.y + e1*dy
  p.pik_append_xy("<polygon points=\"", t.x, t.y)
  p.pik_append_xy(" ",bx-ddx, by-ddy)
  p.pik_append_xy(" ",bx+ddx, by+ddy)
  p.pik_append_clr("\" style=\"fill:",pObj.color,"\"/>\n",false)
  pik_chop(f,t,h/2)
}

/*
** Compute the relative offset to an edge location from the reference for a
** an statement.
*/
func (p *Pik) pik_elem_offset(pObj *PObj, cp uint8) PPoint {
  return pObj.typ.xOffset(p, pObj, cp)
}


/*
** Append raw text to zOut
*/
func (p *Pik) pik_append(zText string){
  p.zOut.WriteString(zText)
}

var ampersand_entity_re = regexp.MustCompile(`^&(?:#[0-9]{2,}|[a-zA-Z][a-zA-Z0-9]+);`)

/*
** Given a string, returns true if the string begins
** with a construct which syntactically matches an HTML entity escape
** sequence (without checking for whether it's a known entity). Always
** returns false if zText[0] is false or n<4. Entities match the
** equivalent of the regexes `&#[0-9]{2,};` and
** `&[a-zA-Z][a-zA-Z0-9]+;`.
*/
func pik_isentity(zText string) bool {
  /* Note that &#nn; values nn<32d are not legal entities. */
  return ampersand_entity_re.MatchString(zText)
}


var html_re_with_space = regexp.MustCompile(`[<> ]`)

/*
** Append text to zOut with HTML characters escaped.
**
**   *  The space character is changed into non-breaking space (U+00a0)
**      if mFlags has the 0x01 bit set. This is needed when outputting
**      text to preserve leading and trailing whitespace.  Turns out we
**      cannot use &nbsp; as that is an HTML-ism and is not valid in XML.
**
**   *  The "&" character is changed into "&amp;" if mFlags has the
**      0x02 bit set.  This is needed when generating error message text.
**
**   *  Except for the above, only "<" and ">" are escaped.
*/
func (p *Pik) pik_append_text(zText string, mFlags int) {
  bQSpace := mFlags&1 > 0
  bQAmp := mFlags&2 > 0

  text := html_re_with_space.ReplaceAllStringFunc(zText, func(s string) string {
    switch {
    case s == "<":
      return "&lt;"
    case s == ">":
      return "&gt;"
    case s == " " && bQSpace:
      return "\302\240"
    default:
      return s
    }
  })
  if !bQAmp {
    p.pik_append(text)
  } else {
    pieces := strings.Split(text, "&")
    p.pik_append(pieces[0])
    for _, piece := range pieces[1:] {
      if pik_isentity("&"+piece) {
        p.pik_append("&")
      } else {
        p.pik_append("&amp;")
      }
      p.pik_append(piece)
    }
  }
}

/*
** Append error message text.  This is either a raw append, or an append
** with HTML escapes, depending on whether the PIKCHR_PLAINTEXT_ERRORS flag
** is set.
*/
func (p *Pik) pik_append_errtxt(zText string) {
  if p.mFlags & PIKCHR_PLAINTEXT_ERRORS != 0{
    p.pik_append(zText)
  }else{
    p.pik_append_text(zText, 0)
  }
}

/* Append a PNum value
*/
func (p *Pik) pik_append_num(z string, v PNum) {
  p.pik_append(z)
  p.pik_append(fmt.Sprintf("%.10g", v))
}

/* Append a PPoint value  (Used for debugging only)
*/
func (p *Pik) pik_append_point(z string, pPt *PPoint) {
  buf := fmt.Sprintf("%.10g,%.10g", pPt.x, pPt.y)
  p.pik_append(z)
  p.pik_append(buf)
}

/*
** Invert the RGB color so that it is appropriate for dark mode.
** Variable x hold the initial color.  The color is intended for use
** as a background color if isBg is true, and as a foreground color
** if isBg is false.
*/
func pik_color_to_dark_mode(x int, isBg bool) int {
  x = 0xffffff - x
  r := (x>>16) & 0xff
  g := (x>>8) & 0xff
  b := x & 0xff
  mx := r
  if g>mx { mx = g }
  if b>mx { mx = b }
  mn := r
  if g<mn { mn = g }
  if b<mn { mn = b }
  r = mn + (mx-r)
  g = mn + (mx-g)
  b = mn + (mx-b)
  if isBg {
    if mx>127 {
      r = (127*r)/mx
      g = (127*g)/mx
      b = (127*b)/mx
    }
  } else {
    if mn<128 && mx>mn {
      r = 127 + ((r-mn)*128)/(mx-mn)
      g = 127 + ((g-mn)*128)/(mx-mn)
      b = 127 + ((b-mn)*128)/(mx-mn)
    }
  }
  return r*0x10000 + g*0x100 + b
}

/* Append a PNum value surrounded by text.  Do coordinate transformations
** on the value.
*/
func (p *Pik) pik_append_x(z1 string, v PNum, z2 string) {
  v -= p.bbox.sw.x
  p.pik_append(fmt.Sprintf("%s%.6g%s", z1, p.rScale*v, z2))
}
func (p *Pik) pik_append_y(z1 string, v PNum, z2 string) {
  v = p.bbox.ne.y - v
  p.pik_append(fmt.Sprintf("%s%.6g%s", z1, p.rScale*v, z2))
}
func (p *Pik) pik_append_xy(z1 string, x PNum, y PNum) {
  x = x - p.bbox.sw.x
  y = p.bbox.ne.y - y
  p.pik_append(fmt.Sprintf("%s%.6g,%.6g", z1, p.rScale*x, p.rScale*y))
}
func (p *Pik) pik_append_dis(z1 string, v PNum, z2 string) {
  p.pik_append(fmt.Sprintf("%s%.6g%s", z1, p.rScale*v, z2))
}

/* Append a color specification to the output.
**
** In PIKCHR_DARK_MODE, the color is inverted.  The "bg" flags indicates that
** the color is intended for use as a background color if true, or as a
** foreground color if false.  The distinction only matters for color
** inversions in PIKCHR_DARK_MODE.
*/
func (p *Pik) pik_append_clr(z1 string,v PNum,z2 string,bg bool) {
  x := pik_round(v)
  if x==0 && p.fgcolor>0 && !bg {
    x = p.fgcolor
  } else if bg && x>=0xffffff && p.bgcolor>0 {
    x = p.bgcolor
  } else if p.mFlags&PIKCHR_DARK_MODE != 0 {
    x = pik_color_to_dark_mode(x,bg)
  }
  r := (x>>16) & 0xff
  g := (x>>8) & 0xff
  b := x & 0xff
  buf := fmt.Sprintf("%srgb(%d,%d,%d)%s", z1, r, g, b, z2)
  p.pik_append(buf)
}

/* Append an SVG path A record:
**
**    A r1 r2 0 0 0 x y
*/
func (p *Pik) pik_append_arc(r1 PNum, r2 PNum, x PNum, y PNum) {
  x = x - p.bbox.sw.x
  y = p.bbox.ne.y - y
  buf := fmt.Sprintf("A%.6g %.6g 0 0 0 %.6g %.6g",
     p.rScale*r1, p.rScale*r2,
     p.rScale*x, p.rScale*y)
  p.pik_append(buf)
}

/* Append a style="..." text.  But, leave the quote unterminated, in case
** the caller wants to add some more.
**
** eFill is non-zero to fill in the background, or 0 if no fill should
** occur.  Non-zero values of eFill determine the "bg" flag to pik_append_clr()
** for cases when pObj.fill==pObj.color
**
**     1        fill is background, and color is foreground.
**     2        fill and color are both foreground.  (Used by "dot" objects)
**     3        fill and color are both background.  (Used by most other objs)
*/
func (p *Pik) pik_append_style(pObj *PObj, eFill int) {
  clrIsBg := false
  p.pik_append(" style=\"")
  if pObj.fill>=0 && eFill != 0 {
    fillIsBg := true
    if pObj.fill==pObj.color {
      if eFill==2 { fillIsBg = false }
      if eFill==3 { clrIsBg = true }
    }
    p.pik_append_clr("fill:", pObj.fill, ";", fillIsBg)
  } else {
    p.pik_append("fill:none;")
  }
  if pObj.sw>=0.0 && pObj.color>=0.0 {
    sw := pObj.sw
    p.pik_append_dis("stroke-width:", sw, ";")
    if pObj.nPath>2 && pObj.rad<=pObj.sw {
      p.pik_append("stroke-linejoin:round;")
    }
    p.pik_append_clr("stroke:",pObj.color,";",clrIsBg)
    if pObj.dotted>0.0 {
      v := pObj.dotted
      if sw<2.1/p.rScale { sw = 2.1/p.rScale }
      p.pik_append_dis("stroke-dasharray:",sw,"")
      p.pik_append_dis(",",v,";")
    } else if pObj.dashed>0.0 {
      v := pObj.dashed
      p.pik_append_dis("stroke-dasharray:",v,"")
      p.pik_append_dis(",",v,";")
    }
  }
}

/*
** Compute the vertical locations for all text items in the
** object pObj.  In other words, set every pObj.aTxt[*].eCode
** value to contain exactly one of: TP_ABOVE2, TP_ABOVE, TP_CENTER,
** TP_BELOW, or TP_BELOW2 is set.
*/
func pik_txt_vertical_layout(pObj *PObj) {
  n := int(pObj.nTxt)
  if n==0 { return }
  aTxt := pObj.aTxt[:]
  if n==1 {
    if (aTxt[0].eCode & TP_VMASK)==0 {
      aTxt[0].eCode |= TP_CENTER
    }
  } else {
    allSlots := int16(0)
    var aFree [5]int16
    var iSlot int
    /* If there is more than one TP_ABOVE, change the first to TP_ABOVE2. */
    for j, mJust, i := 0, int16(0), n-1; i>=0; i-- {
      if aTxt[i].eCode&TP_ABOVE != 0 {
        if j==0 {
          j++
          mJust = aTxt[i].eCode&TP_JMASK
        } else if j==1 && mJust!=0 && (aTxt[i].eCode&mJust)==0 {
          j++
        } else {
          aTxt[i].eCode = (aTxt[i].eCode&^TP_VMASK) | TP_ABOVE2
          break
        }
      }
    }
    /* If there is more than one TP_BELOW, change the last to TP_BELOW2 */
    for j, mJust, i := 0, int16(0), 0; i<n; i++ {
      if aTxt[i].eCode&TP_BELOW != 0 {
        if j==0 {
          j++
          mJust = aTxt[i].eCode&TP_JMASK
        } else if j==1 && mJust!=0 && (aTxt[i].eCode & mJust)==0 {
          j++
        } else {
          aTxt[i].eCode = (aTxt[i].eCode &^ TP_VMASK) | TP_BELOW2
          break
        }
      }
    }
    /* Compute a mask of all slots used */
    for i:=0; i<n; i++ { allSlots |= aTxt[i].eCode & TP_VMASK }
    /* Set of an array of available slots */
    if n==2 && ((aTxt[0].eCode|aTxt[1].eCode)&TP_JMASK)==(TP_LJUST|TP_RJUST) {
      /* Special case of two texts that have opposite justification:
      ** Allow them both to float to center. */
      iSlot = 2
      aFree[0] = TP_CENTER
      aFree[1] = TP_CENTER
    } else {
      /* Set up the arrow so that available slots are filled from top to
      ** bottom */
      iSlot = 0
      if n>=4 && (allSlots & TP_ABOVE2)==0 { aFree[iSlot] = TP_ABOVE2; iSlot++ }
      if (allSlots & TP_ABOVE)==0 { aFree[iSlot] = TP_ABOVE; iSlot++ }
      if (n&1)!=0 { aFree[iSlot] = TP_CENTER; iSlot++ }
      if (allSlots & TP_BELOW)==0 { aFree[iSlot] = TP_BELOW; iSlot++ }
      if n>=4 && (allSlots & TP_BELOW2)==0 { aFree[iSlot] = TP_BELOW2; iSlot++ }
    }
    /* Set the VMASK for all unassigned texts */
    for i, iSlot := 0, 0; i<n; i++ {
      if (aTxt[i].eCode & TP_VMASK)==0 {
        aTxt[i].eCode |= aFree[iSlot]
        iSlot++
      }
    }
  }
}

/* Return the font scaling factor associated with the input text attribute.
*/
func pik_font_scale(t PToken) PNum {
  var scale PNum = 1.0
  if t.eCode&TP_BIG != 0   { scale *= 1.25 }
  if t.eCode&TP_SMALL != 0 { scale *= 0.8 }
  if t.eCode&TP_XTRA != 0  { scale *= scale }
  return scale
}

/* Append multiple <text> SVG elements for the text fields of the PObj.
** Parameters:
**
**    p          The Pik object into which we are rendering
**
**    pObj       Object containing the text to be rendered
**
**    pBox       If not NULL, do no rendering at all.  Instead
**               expand the box object so that it will include all
**               of the text.
*/
func (p *Pik) pik_append_txt(pObj *PObj, pBox *PBox) {
  var jw PNum          /* Justification margin relative to center */
  var ha2 PNum = 0.0   /* Height of the top row of text */
  var ha1 PNum = 0.0   /* Height of the second "above" row */
  var hc PNum = 0.0    /* Height of the center row */
  var hb1 PNum = 0.0   /* Height of the first "below" row of text */
  var hb2 PNum = 0.0   /* Height of the second "below" row */
  var yBase PNum = 0.0
  var sw PNum = pObj.sw
  if sw < 0 {
    sw = 0
  }
  allMask := int16(0)

  if p.nErr != 0 { return }
  if pObj.nTxt==0 { return }
  aTxt := pObj.aTxt[:]
  n := int(pObj.nTxt)
  pik_txt_vertical_layout(pObj)
  x := pObj.ptAt.x
  for i:=0; i<n; i++ { allMask |= pObj.aTxt[i].eCode }
  if pObj.typ.isLine {
    hc = sw*1.5
  } else if pObj.rad>0.0 && pObj.typ.zName=="cylinder" {
    yBase = -0.75*pObj.rad
  }
  if allMask&TP_CENTER != 0 {
    for i:=0; i<n; i++ {
      if pObj.aTxt[i].eCode&TP_CENTER != 0 {
        s := pik_font_scale(pObj.aTxt[i])
        if hc<s*p.charHeight { hc = s*p.charHeight }
      }
    }
  }
  if allMask&TP_ABOVE != 0 {
    for i:=0; i<n; i++ {
      if pObj.aTxt[i].eCode&TP_ABOVE != 0 {
        s := pik_font_scale(pObj.aTxt[i])*p.charHeight
        if ha1<s { ha1 = s }
      }
    }
    if allMask&TP_ABOVE2 != 0 {
      for i:=0; i<n; i++ {
        if pObj.aTxt[i].eCode&TP_ABOVE2 != 0 {
          s := pik_font_scale(pObj.aTxt[i])*p.charHeight
          if ha2<s { ha2 = s }
        }
      }
    }
  }
  if allMask&TP_BELOW != 0 {
    for i:=0; i<n; i++ {
      if pObj.aTxt[i].eCode&TP_BELOW != 0 {
        s := pik_font_scale(pObj.aTxt[i])*p.charHeight
        if hb1<s { hb1 = s }
      }
    }
    if allMask&TP_BELOW2 != 0 {
      for i:=0; i<n; i++ {
        if pObj.aTxt[i].eCode&TP_BELOW2 != 0 {
          s := pik_font_scale(pObj.aTxt[i])*p.charHeight
          if hb2<s { hb2 = s }
        }
      }
    }
  }
  if pObj.typ.eJust==1 {
    jw = 0.5*(pObj.w - 0.5*(p.charWidth + sw))
  }else{
    jw = 0.0
  }
  for i:=0; i<n; i++ {
    t := aTxt[i]
    xtraFontScale := pik_font_scale(t)
    var nx PNum = 0
    orig_y := pObj.ptAt.y
    y := yBase
    if t.eCode&TP_ABOVE2 != 0 { y += 0.5*hc + ha1 + 0.5*ha2 }
    if t.eCode&TP_ABOVE  != 0 { y += 0.5*hc + 0.5*ha1 }
    if t.eCode&TP_BELOW  != 0 { y -= 0.5*hc + 0.5*hb1 }
    if t.eCode&TP_BELOW2 != 0 { y -= 0.5*hc + hb1 + 0.5*hb2 }
    if t.eCode&TP_LJUST  != 0 { nx -= jw }
    if t.eCode&TP_RJUST  != 0 { nx += jw }

    if pBox!=nil {
      /* If pBox is not NULL, do not draw any <text>.  Instead, just expand
      ** pBox to include the text */
      var cw PNum = PNum(pik_text_length(t, t.eCode&TP_MONO != 0))*p.charWidth*xtraFontScale*0.01
      var ch PNum = p.charHeight*0.5*xtraFontScale
      var x0, y0, x1, y1 PNum  /* Boundary of text relative to pObj.ptAt */
      if t.eCode&(TP_BOLD|TP_MONO) == TP_BOLD {
         cw *= 1.1
      }
      if t.eCode&TP_RJUST != 0 {
        x0 = nx
        y0 = y-ch
        x1 = nx-cw
        y1 = y+ch
      } else if  t.eCode&TP_LJUST != 0 {
        x0 = nx
        y0 = y-ch
        x1 = nx+cw
        y1 = y+ch
      } else {
        x0 = nx+cw/2
        y0 = y+ch
        x1 = nx-cw/2
        y1 = y-ch
      }
      if (t.eCode&TP_ALIGN)!=0 && pObj.nPath>=2 {
        nn := pObj.nPath
        var dx PNum = pObj.aPath[nn-1].x - pObj.aPath[0].x
        var dy PNum = pObj.aPath[nn-1].y - pObj.aPath[0].y
        if dx!=0 || dy!=0 {
          var dist PNum = math.Hypot(dx,dy)
          var tt PNum
          dx /= dist
          dy /= dist
          tt = dx*x0 - dy*y0
          y0 = dy*x0 - dx*y0
          x0 = tt
          tt = dx*x1 - dy*y1
          y1 = dy*x1 - dx*y1
          x1 = tt
        }
      }
      pik_bbox_add_xy(pBox, x+x0, orig_y+y0)
      pik_bbox_add_xy(pBox, x+x1, orig_y+y1)
      continue
    }
    nx += x
    y += orig_y

    p.pik_append_x("<text x=\"", nx, "\"")
    p.pik_append_y(" y=\"", y, "\"")
    if t.eCode&TP_RJUST != 0 {
      p.pik_append(" text-anchor=\"end\"")
    } else if t.eCode&TP_LJUST != 0 {
      p.pik_append(" text-anchor=\"start\"")
    } else {
      p.pik_append(" text-anchor=\"middle\"")
    }
    if t.eCode&TP_ITALIC != 0 {
      p.pik_append(" font-style=\"italic\"")
    }
    if t.eCode&TP_BOLD != 0 {
      p.pik_append(" font-weight=\"bold\"")
    }
    if t.eCode&TP_MONO != 0 {
      p.pik_append(" font-family=\"monospace\"")
    }
    if pObj.color>=0.0 {
      p.pik_append_clr(" fill=\"", pObj.color, "\"",false)
    }
    xtraFontScale *= p.fontScale
    if xtraFontScale<=0.99 || xtraFontScale>=1.01 {
      p.pik_append_num(" font-size=\"", xtraFontScale*100.0)
      p.pik_append("%\"")
    }
    if (t.eCode&TP_ALIGN)!=0 && pObj.nPath>=2 {
      nn := pObj.nPath
      var dx PNum = pObj.aPath[nn-1].x - pObj.aPath[0].x
      var dy PNum = pObj.aPath[nn-1].y - pObj.aPath[0].y
      if dx!=0 || dy!=0 {
        var ang PNum = math.Atan2(dy,dx)*-180/math.Pi
        p.pik_append_num(" transform=\"rotate(", ang)
        p.pik_append_xy(" ", x, orig_y)
        p.pik_append(")\"")
      }
    }
    p.pik_append(" dominant-baseline=\"central\">")
    var z []byte
    var nz int
    if t.n>=2 && t.z[0]=='"' {
      z = t.z[1:]
      nz = t.n-2
    } else {
      z = t.z
      nz = t.n
    }
    for nz>0 {
      var j int
      for j=0; j<nz && z[j]!='\\'; j++ {}
      if j != 0 { p.pik_append_text(string(z[:j]), 0x3) }
      if j<nz && (j+1==nz || z[j+1]=='\\') {
        p.pik_append("&#92;")
        j++
      }
      nz -= j+1
      if nz>0 {
        z = z[j+1:]
      }
    }
    p.pik_append("</text>\n")
  }
}

/*
** Append text (that will go inside of a <pre>...</pre>) that
** shows the context of an error token.
*/
func (p *Pik) pik_error_context(pErr *PToken, nContext int){
  var (
    iErrPt int            /* Index of first byte of error from start of input */
    iErrCol int           /* Column of the error token on its line */
    iStart int            /* Start position of the error context */
    iEnd int              /* End position of the error context */
    iLineno int           /* Line number of the error */
    iFirstLineno int      /* Line number of start of error context */
    i int                 /* Loop counter */
    iBump = 0             /* Bump the location of the error cursor */
  )

  iErrPt = len(p.sIn.z) - len(pErr.z) // in C, uses pointer math: iErrPt = (int)(pErr->z - p->sIn.z);
  if iErrPt>=p.sIn.n {
    iErrPt = p.sIn.n-1
    iBump = 1
  }else{
    for iErrPt>0 && (p.sIn.z[iErrPt]=='\n' || p.sIn.z[iErrPt]=='\r') {
      iErrPt--
      iBump = 1
    }
  }
  iLineno = 1
  for i=0; i<iErrPt; i++{
    if p.sIn.z[i]=='\n' {
      iLineno++
    }
  }
  iStart = 0
  iFirstLineno = 1
  for iFirstLineno+nContext<iLineno {
    for p.sIn.z[iStart]!='\n' { iStart++ }
    iStart++
    iFirstLineno++
  }
  for iEnd=iErrPt; p.sIn.z[iEnd]!=0 && p.sIn.z[iEnd]!='\n'; iEnd++ {}
  i = iStart
  for iFirstLineno<=iLineno {
    zLineno := fmt.Sprintf("/* %4d */  ", iFirstLineno)
    iFirstLineno++
    p.pik_append(zLineno)
    for i=iStart; p.sIn.z[i]!=0 && p.sIn.z[i]!='\n'; i++ {}
    p.pik_append_errtxt(string(p.sIn.z[iStart:i]))
    iStart = i+1
    p.pik_append("\n")
  }
  for iErrCol, i = 0, iErrPt; i>0 && p.sIn.z[i]!='\n'; iErrCol, i = iErrCol+1, i-1 {}
  for i=0; i<iErrCol+11+iBump; i++ { p.pik_append(" ") }
  for i=0; i<pErr.n; i++ { p.pik_append("^") }
  p.pik_append("\n")
}


/*
** Generate an error message for the output.  pErr is the token at which
** the error should point.  zMsg is the text of the error message. If
** either pErr or zMsg is NULL, generate an out-of-memory error message.
**
** This routine is a no-op if there has already been an error reported.
*/
func (p *Pik) pik_error(pErr *PToken, zMsg string){
  if p==nil { return }
  if p.nErr > 0 { return }
  p.nErr++
  if zMsg=="" {
    if p.mFlags & PIKCHR_PLAINTEXT_ERRORS != 0 {
      p.pik_append("\nOut of memory\n")
    } else {
      p.pik_append("\n<div><p>Out of memory</p></div>\n")
    }
    return
  }
  if pErr==nil {
    p.pik_append("\n")
    p.pik_append_errtxt(zMsg)
    return
  }
  if (p.mFlags & PIKCHR_PLAINTEXT_ERRORS)==0 {
    p.pik_append("<div><pre>\n")
  }
  p.pik_error_context(pErr, 5)
  p.pik_append("ERROR: ")
  p.pik_append_errtxt(zMsg)
  p.pik_append("\n")
  for i:=p.nCtx-1; i>=0; i-- {
    p.pik_append("Called from:\n")
    p.pik_error_context(&p.aCtx[i], 0)
  }
  if (p.mFlags & PIKCHR_PLAINTEXT_ERRORS)==0 {
    p.pik_append("</pre></div>\n")
  }
}

/*
 ** Process an "assert( e1 == e2 )" statement.  Always return `nil`.
 */
func (p *Pik) pik_assert(e1 PNum, pEq *PToken, e2 PNum) *PObj {
  /* Convert the numbers to strings using %g for comparison.  This
   ** limits the precision of the comparison to account for rounding error. */
  zE1 := fmt.Sprintf("%.6g", e1)
  zE2 := fmt.Sprintf("%.6g", e2)
  if zE1 != zE2 {
    p.pik_error(pEq, fmt.Sprintf("%.50s != %.50s", zE1, zE2))
  }
  return nil
}

/*
** Process an "assert( place1 == place2 )" statement.  Always return `nil`.
*/
func (p *Pik) pik_position_assert(e1 *PPoint, pEq *PToken, e2 *PPoint) *PObj{
  /* Convert the numbers to strings using %g for comparison.  This
   ** limits the precision of the comparison to account for rounding error. */
  zE1 := fmt.Sprintf("(%.6g,%.6g)", e1.x, e1.y)
  zE2 := fmt.Sprintf("(%.6g,%.6g)", e2.x, e2.y)
  if zE1 != zE2 {
    p.pik_error(pEq, fmt.Sprintf("%s != %s", zE1, zE2))
  }
  return nil
}

/* Free a complete list of objects */
func (p *Pik) pik_elist_free(pList *PList){
  if pList==nil || *pList==nil { return }
  for i:=0; i<len(*pList); i++ {
    p.pik_elem_free((*pList)[i])
  }
}

/* Free a single object, and its substructure */
func (p *Pik) pik_elem_free(pObj *PObj){
  if pObj==nil { return }
  p.pik_elist_free(&pObj.pSublist)
}

/* Convert a numeric literal into a number.  Return that number.
** There is no error handling because the tokenizer has already
** assured us that the numeric literal is valid.
**
** Allowed number forms:
**
**   (1)    Floating point literal
**   (2)    Same as (1) but followed by a unit: "cm", "mm", "in",
**          "px", "pt", or "pc".
**   (3)    Hex integers: 0x000000
**
** This routine returns the result in inches.  If a different unit
** is specified, the conversion happens automatically.
*/
func pik_atof(num *PToken) PNum {
  if num.n>=3 && num.z[0]=='0' && (num.z[1]=='x'||num.z[1]=='X') {
    i, err := strconv.ParseInt(string(num.z[2:num.n]), 16, 64)
    if err != nil {
      return 0
    }
    return PNum(i)
  }
  factor := 1.0

  z := num.String()

  if num.n > 2 {
    hasSuffix := true
    switch string(num.z[num.n-2:num.n]) {
    case "cm": factor = 1/2.54
    case "mm": factor = 1/25.4
    case "px": factor = 1/96.0
    case "pt": factor = 1/72.0
    case "pc": factor = 1/6.0
    case "in": factor = 1.0
    default: hasSuffix = false
    }
    if hasSuffix {
      z = z[:len(z)-2]
    }
  }

  ans, err := strconv.ParseFloat(z, 64)
  ans *= factor
  if err != nil {
    return 0.0
  }
  return PNum(ans)
}

/*
** Compute the distance between two points
*/
func pik_dist(pA *PPoint, pB *PPoint) PNum {
  dx := pB.x - pA.x
  dy := pB.y - pA.y
  return math.Hypot(dx,dy)
}

/* Return true if a bounding box is empty.
*/
func pik_bbox_isempty(p *PBox) bool {
  return p.sw.x>p.ne.x
}

/* Return true if point pPt is contained within the bounding box pBox
*/
func pik_bbox_contains_point(pBox *PBox, pPt *PPoint) bool {
  if pik_bbox_isempty(pBox) { return false }
  if pPt.x < pBox.sw.x { return false }
  if pPt.x > pBox.ne.x { return false }
  if pPt.y < pBox.sw.y { return false }
  if pPt.y > pBox.ne.y { return false }
  return true
}

/* Initialize a bounding box to an empty container
*/
func pik_bbox_init(p *PBox) {
  p.sw.x = 1.0
  p.sw.y = 1.0
  p.ne.x = 0.0
  p.ne.y = 0.0
}

/* Enlarge the PBox of the first argument so that it fully
** covers the second PBox
*/
func pik_bbox_addbox(pA *PBox, pB *PBox) {
  if pik_bbox_isempty(pA) {
    *pA = *pB
  }
  if pik_bbox_isempty(pB) { return }
  if pA.sw.x>pB.sw.x { pA.sw.x = pB.sw.x }
  if pA.sw.y>pB.sw.y { pA.sw.y = pB.sw.y }
  if pA.ne.x<pB.ne.x { pA.ne.x = pB.ne.x }
  if pA.ne.y<pB.ne.y { pA.ne.y = pB.ne.y }
}

/* Enlarge the PBox of the first argument, if necessary, so that
** it contains the point described by the 2nd and 3rd arguments.
*/
func pik_bbox_add_xy(pA *PBox, x PNum, y PNum) {
  if pik_bbox_isempty(pA) {
    pA.ne.x = x
    pA.ne.y = y
    pA.sw.x = x
    pA.sw.y = y
    return
  }
  if pA.sw.x>x { pA.sw.x = x }
  if pA.sw.y>y { pA.sw.y = y }
  if pA.ne.x<x { pA.ne.x = x }
  if pA.ne.y<y { pA.ne.y = y }
}

/* Enlarge the PBox so that it is able to contain an ellipse
** centered at x,y and with radiuses rx and ry.
*/
func pik_bbox_addellipse(pA *PBox, x PNum, y PNum, rx PNum, ry PNum) {
  if pik_bbox_isempty(pA) {
    pA.ne.x = x+rx
    pA.ne.y = y+ry
    pA.sw.x = x-rx
    pA.sw.y = y-ry
    return
  }
  if pA.sw.x>x-rx { pA.sw.x = x-rx }
  if pA.sw.y>y-ry { pA.sw.y = y-ry }
  if pA.ne.x<x+rx { pA.ne.x = x+rx }
  if pA.ne.y<y+ry { pA.ne.y = y+ry }
}


/* Append a new object onto the end of an object list.  The
** object list is created if it does not already exist.  Return
** the new object list.
*/
func (p *Pik) pik_elist_append(pList PList, pObj *PObj) PList {
  if pObj == nil {
    return pList
  }
  pList = append(pList, pObj)
  p.list = pList
  return pList
}

/* Convert an object class name into a PClass pointer
*/
func pik_find_class(pId *PToken) *PClass {
  zString := pId.String()
  first := 0
  last := len(aClass) - 1
  for {
    mid := (first+last)/2
    c := strings.Compare(aClass[mid].zName, zString)
    if c==0 {
      return &aClass[mid]
    }
    if c<0 {
      first = mid + 1
    } else {
      last = mid - 1
    }

    if first > last {
      return nil
    }
  }
}

/* Allocate and return a new PObj object.
**
** If pId!=0 then pId is an identifier that defines the object class.
** If pStr!=0 then it is a STRING literal that defines a text object.
** If pSublist!=0 then this is a [...] object. If all three parameters
** are NULL then this is a no-op object used to define a PLACENAME.
*/
func (p *Pik) pik_elem_new(pId *PToken, pStr *PToken,pSublist PList) *PObj {
  miss := false
  if p.nErr != 0 {
    return nil
  }
  pNew := &PObj{}

  p.cur = pNew
  p.nTPath = 1
  p.thenFlag = false
  if len(p.list) == 0 {
    pNew.ptAt.x = 0.0
    pNew.ptAt.y = 0.0
    pNew.eWith = CP_C
  } else {
    pPrior := p.list[len(p.list)-1]
    pNew.ptAt = pPrior.ptExit
    switch p.eDir {
      default:         pNew.eWith = CP_W
      case DIR_LEFT:   pNew.eWith = CP_E
      case DIR_UP:     pNew.eWith = CP_S
      case DIR_DOWN:   pNew.eWith = CP_N
    }
  }
  p.aTPath[0] = pNew.ptAt
  pNew.with = pNew.ptAt
  pNew.outDir = p.eDir
  pNew.inDir = p.eDir
  pNew.iLayer = p.pik_value_int("layer", &miss)
  if miss { pNew.iLayer = 1000 }
  if pNew.iLayer<0 { pNew.iLayer = 0 }
  if pSublist != nil {
    pNew.typ = &sublistClass
    pNew.pSublist = pSublist
    sublistClass.xInit(p,pNew)
    return pNew
  }
  if pStr != nil {
    n := PToken{
      z: []byte("text"),
      n: 4,
    }
    pNew.typ = pik_find_class(&n)
    assert( pNew.typ!=nil, "pNew.typ!=nil" )
    pNew.errTok = *pStr
    pNew.typ.xInit(p, pNew)
    p.pik_add_txt(pStr, pStr.eCode)
    return pNew
  }
  if pId != nil {
    pNew.errTok = *pId
    pClass := pik_find_class(pId)
    if pClass != nil {
      pNew.typ = pClass
      pNew.sw = p.pik_value("thickness",nil)
      pNew.fill = p.pik_value("fill",nil)
      pNew.color = p.pik_value("color",nil)
      pClass.xInit(p, pNew)
      return pNew
    }
    p.pik_error(pId, "unknown object type")
    p.pik_elem_free(pNew)
    return nil
  }
  pNew.typ = &noopClass
  pNew.ptExit = pNew.ptAt
  pNew.ptEnter = pNew.ptAt
  return pNew
}

/*
** If the ID token in the argument is the name of a macro, return
** the PMacro object for that macro
*/
func (p *Pik) pik_find_macro(pId *PToken) *PMacro {
  for pMac := p.pMacros; pMac != nil; pMac=pMac.pNext {
    if pMac.macroName.n==pId.n && bytesEq(pMac.macroName.z[:pMac.macroName.n], pId.z[:pId.n]) {
      return pMac
    }
  }
  return nil
}

/* Add a new macro
*/
func (p *Pik) pik_add_macro(
  pId *PToken,      /* The ID token that defines the macro name */
  pCode *PToken,    /* Macro body inside of {...} */
){
  pNew := p.pik_find_macro(pId)
  if pNew==nil {
    pNew = &PMacro{
      pNext: p.pMacros,
      macroName: *pId,
    }
    p.pMacros = pNew
  }
  pNew.macroBody.z = pCode.z[1:]
  pNew.macroBody.n = pCode.n-2
  pNew.inUse = false
}


/*
** Set the output direction and exit point for an object
*/
func pik_elem_set_exit(pObj *PObj, eDir uint8) {
  assert( ValidDir(eDir), "ValidDir(eDir)" )
  pObj.outDir = eDir
  if !pObj.typ.isLine || pObj.bClose {
    pObj.ptExit = pObj.ptAt
    switch pObj.outDir {
      default:         pObj.ptExit.x += pObj.w*0.5
      case DIR_LEFT:   pObj.ptExit.x -= pObj.w*0.5
      case DIR_UP:     pObj.ptExit.y += pObj.h*0.5
      case DIR_DOWN:   pObj.ptExit.y -= pObj.h*0.5
    }
  }
}

/* Change the layout direction.
*/
func (p *Pik) pik_set_direction(eDir uint8){
  assert( ValidDir(eDir), "ValidDir(eDir)" )
  p.eDir = eDir

  /* It seems to make sense to reach back into the last object and
  ** change its exit point (its ".end") to correspond to the new
  ** direction.  Things just seem to work better this way.  However,
  ** legacy PIC does *not* do this.
  **
  ** The difference can be seen in a script like this:
  **
  **      arrow; circle; down; arrow
  **
  ** You can make pikchr render the above exactly like PIC
  ** by deleting the following three lines.  But I (drh) think
  ** it works better with those lines in place.
  */
  if len(p.list) > 0 {
    pik_elem_set_exit(p.list[len(p.list)-1], eDir)
  }
}

/* Move all coordinates contained within an object (and within its
** substructure) by dx, dy
*/
func pik_elem_move(pObj *PObj, dx PNum, dy PNum) {
  pObj.ptAt.x += dx
  pObj.ptAt.y += dy
  pObj.ptEnter.x += dx
  pObj.ptEnter.y += dy
  pObj.ptExit.x += dx
  pObj.ptExit.y += dy
  pObj.bbox.ne.x += dx
  pObj.bbox.ne.y += dy
  pObj.bbox.sw.x += dx
  pObj.bbox.sw.y += dy
  for i:=0; i<pObj.nPath; i++ {
    pObj.aPath[i].x += dx
    pObj.aPath[i].y += dy
  }
  if pObj.pSublist != nil {
    pik_elist_move(pObj.pSublist, dx, dy)
  }
}
func pik_elist_move(pList PList, dx PNum, dy PNum) {
  for i:=0; i<len(pList); i++ {
    pik_elem_move(pList[i], dx, dy)
  }
}

/*
** Check to see if it is ok to set the value of paraemeter mThis.
** Return 0 if it is ok. If it not ok, generate an appropriate
** error message and return non-zero.
**
** Flags are set in pObj so that the same object or conflicting
** objects may not be set again.
**
** To be ok, bit mThis must be clear and no more than one of
** the bits identified by mBlockers may be set.
*/
func (p *Pik) pik_param_ok(
  pObj *PObj,       /* The object under construction */
  pId *PToken,      /* Make the error point to this token */
  mThis uint,       /* Value we are trying to set */
) bool {
  if pObj.mProp&mThis != 0 {
    p.pik_error(pId, "value is already set")
    return true
  }
  if pObj.mCalc&mThis != 0 {
    p.pik_error(pId, "value already fixed by prior constraints")
    return true
  }
  pObj.mProp |= mThis
  return false
}


/*
** Set a numeric property like "width 7" or "radius 200%".
**
** The rAbs term is an absolute value to add in.  rRel is
** a relative value by which to change the current value.
*/
func (p *Pik) pik_set_numprop(pId *PToken, pVal *PRel) {
  pObj := p.cur
  switch pId.eType {
  case T_HEIGHT:
    if p.pik_param_ok(pObj, pId, A_HEIGHT) { return }
    pObj.h = pObj.h*pVal.rRel + pVal.rAbs
  case T_WIDTH:
    if p.pik_param_ok(pObj, pId, A_WIDTH) { return }
    pObj.w = pObj.w*pVal.rRel + pVal.rAbs
  case T_RADIUS:
    if p.pik_param_ok(pObj, pId, A_RADIUS) { return }
    pObj.rad = pObj.rad*pVal.rRel + pVal.rAbs
  case T_DIAMETER:
    if p.pik_param_ok(pObj, pId, A_RADIUS) { return }
    pObj.rad = pObj.rad*pVal.rRel + 0.5*pVal.rAbs /* diam it 2x rad */
  case T_THICKNESS:
    if p.pik_param_ok(pObj, pId, A_THICKNESS) { return }
    pObj.sw = pObj.sw*pVal.rRel + pVal.rAbs
  }
  if pObj.typ.xNumProp != nil {
    pObj.typ.xNumProp(p, pObj, pId)
  }
}

/*
** Set a color property.  The argument is an RGB value.
*/
func (p *Pik) pik_set_clrprop(pId *PToken, rClr PNum) {
  pObj := p.cur
  switch pId.eType {
  case T_FILL:
    if p.pik_param_ok(pObj, pId, A_FILL) { return }
    pObj.fill = rClr
  case T_COLOR:
    if p.pik_param_ok(pObj, pId, A_COLOR) { return }
    pObj.color = rClr
    break
  }
  if pObj.typ.xNumProp != nil {
    pObj.typ.xNumProp(p, pObj, pId)
  }
}

/*
** Set a "dashed" property like "dash 0.05"
**
** Use the value supplied by pVal if available.  If pVal==0, use
** a default.
*/
func (p *Pik) pik_set_dashed(pId *PToken, pVal *PNum) {
  pObj := p.cur
  switch pId.eType {
  case T_DOTTED:
    if pVal != nil {
      pObj.dotted = *pVal
    } else {
      pObj.dotted = p.pik_value("dashwid",nil)
    }
    pObj.dashed = 0.0
  case T_DASHED:
    if pVal != nil {
      pObj.dashed = *pVal
    } else {
      pObj.dashed = p.pik_value("dashwid",nil)
    }
    pObj.dotted = 0.0
  }
}

/*
** If the current path information came from a "same" or "same as"
** reset it.
*/
func (p *Pik) pik_reset_samepath() {
  if p.samePath {
    p.samePath = false
    p.nTPath = 1
  }
}

/* Add a new term to the path for a line-oriented object by transferring
** the information in the ptTo field over onto the path and into ptFrom
** resetting the ptTo.
*/
func (p *Pik) pik_then(pToken *PToken, pObj *PObj) {
  if !pObj.typ.isLine {
    p.pik_error(pToken, "use with line-oriented objects only")
    return
  }
  n := p.nTPath - 1
  if n<1 && (pObj.mProp & A_FROM)==0 {
    p.pik_error(pToken, "no prior path points")
    return
  }
  p.thenFlag = true
}

/* Advance to the next entry in p.aTPath.  Return its index.
*/
func (p *Pik) pik_next_rpath(pErr *PToken) int{
  n := p.nTPath - 1
  if n+1>=len(p.aTPath) {
    (*Pik)(nil).pik_error(pErr, "too many path elements")
    return n
  }
  n++
  p.nTPath++
  p.aTPath[n] = p.aTPath[n-1]
  p.mTPath = 0
  return n
}

/* Add a direction term to an object.  "up 0.5", or "left 3", or "down"
** or "down 50%".
*/
func (p *Pik) pik_add_direction(pDir *PToken, pVal *PRel) {
  pObj := p.cur
  if !pObj.typ.isLine {
    if pDir != nil {
      p.pik_error(pDir, "use with line-oriented objects only")
    } else {
      x := pik_next_semantic_token(&pObj.errTok)
      p.pik_error(&x, "syntax error")
    }
    return
  }
  p.pik_reset_samepath()
  n := p.nTPath - 1
  if p.thenFlag || p.mTPath==3 || n==0 {
    n = p.pik_next_rpath(pDir)
    p.thenFlag = false
  }
  dir := p.eDir
  if pDir != nil {
    dir = uint8(pDir.eCode)
  }
  switch dir {
  case DIR_UP:
    if p.mTPath&2 > 0 { n = p.pik_next_rpath(pDir) }
    p.aTPath[n].y += pVal.rAbs + pObj.h*pVal.rRel
    p.mTPath |= 2
  case DIR_DOWN:
    if p.mTPath&2 > 0 { n = p.pik_next_rpath(pDir) }
    p.aTPath[n].y -= pVal.rAbs + pObj.h*pVal.rRel
    p.mTPath |= 2
  case DIR_RIGHT:
    if p.mTPath&1 > 0 { n = p.pik_next_rpath(pDir) }
    p.aTPath[n].x += pVal.rAbs + pObj.w*pVal.rRel
    p.mTPath |= 1
  case DIR_LEFT:
    if p.mTPath&1 > 0 { n = p.pik_next_rpath(pDir) }
    p.aTPath[n].x -= pVal.rAbs + pObj.w*pVal.rRel
    p.mTPath |= 1
  }
  pObj.outDir = dir
}

/* Process a movement attribute of one of these forms:
**
**         pDist   pHdgKW  rHdg    pEdgept
**     GO distance HEADING angle
**     GO distance               compasspoint
*/
func (p *Pik) pik_move_hdg(
  pDist *PRel,         /* Distance to move */
  pHeading *PToken,    /* "heading" keyword if present */
  rHdg PNum,           /* Angle argument to "heading" keyword */
  pEdgept *PToken,     /* EDGEPT keyword "ne", "sw", etc... */
  pErr *PToken,        /* Token to use for error messages */
){
  pObj := p.cur
  var rDist PNum = pDist.rAbs + p.pik_value("linewid",nil)*pDist.rRel
  if !pObj.typ.isLine {
    p.pik_error(pErr, "use with line-oriented objects only")
    return
  }
  p.pik_reset_samepath()
  n := 0
  for n < 1 {
    n = p.pik_next_rpath(pErr)
  }
  if pHeading != nil {
      rHdg = math.Mod(rHdg, 360)
  } else if pEdgept.eEdge==CP_C {
    p.pik_error(pEdgept, "syntax error")
    return
  } else {
    rHdg = pik_hdg_angle[pEdgept.eEdge]
  }
  if rHdg<=45.0 {
    pObj.outDir = DIR_UP
  } else if rHdg<=135.0 {
    pObj.outDir = DIR_RIGHT
  } else if rHdg<=225.0 {
    pObj.outDir = DIR_DOWN
  } else if rHdg<=315.0 {
    pObj.outDir = DIR_LEFT
  } else {
    pObj.outDir = DIR_UP
  }
  rHdg *= 0.017453292519943295769  /* degrees to radians */
  p.aTPath[n].x += rDist*math.Sin(rHdg)
  p.aTPath[n].y += rDist*math.Cos(rHdg)
  p.mTPath = 2
}

/* Process a movement attribute of the form "right until even with ..."
 **
 ** pDir is the first keyword, "right" or "left" or "up" or "down".
 ** The movement is in that direction until its closest approach to
 ** the point specified by pPoint.
 */
func (p *Pik) pik_evenwith(pDir *PToken, pPlace *PPoint) {
  pObj := p.cur

  if !pObj.typ.isLine {
    p.pik_error(pDir, "use with line-oriented objects only")
    return
  }
  p.pik_reset_samepath()
  n := p.nTPath - 1
  if p.thenFlag || p.mTPath==3 || n==0 {
    n = p.pik_next_rpath(pDir)
    p.thenFlag = false
  }
  switch pDir.eCode {
  case DIR_DOWN, DIR_UP:
    if p.mTPath&2 != 0 { n = p.pik_next_rpath(pDir) }
    p.aTPath[n].y = pPlace.y
    p.mTPath |= 2
  case DIR_RIGHT, DIR_LEFT:
    if p.mTPath&1 != 0 { n = p.pik_next_rpath(pDir) }
    p.aTPath[n].x = pPlace.x
    p.mTPath |= 1
  }
  pObj.outDir = uint8(pDir.eCode)
}

/* If the last referenced object is centered at point pPt then return
** a pointer to that object.  If there is no prior object reference,
** or if the points are not the same, return NULL.
**
** This is a side-channel hack used to find the objects at which a
** line begins and ends.  For example, in
**
**        arrow from OBJ1 to OBJ2 chop
**
** The arrow object is normally just handed the coordinates of the
** centers for OBJ1 and OBJ2.  But we also want to know the specific
** object named in case there are multiple objects centered at the
** same point.
**
** See forum post 1d46e3a0bc
*/
func (p *Pik) pik_last_ref_object(pPt *PPoint) *PObj {
  var pRes *PObj
  if p.lastRef==nil { return nil }
  if p.lastRef.ptAt.x==pPt.x && p.lastRef.ptAt.y==pPt.y {
    pRes = p.lastRef
  }
  p.lastRef = nil
  return pRes
}

/* Set the "from" of an object
*/
func (p *Pik) pik_set_from(pObj *PObj, pTk *PToken, pPt *PPoint) {
  if !pObj.typ.isLine {
    p.pik_error(pTk, "use \"at\" to position this object")
    return
  }
  if pObj.mProp&A_FROM != 0 {
    p.pik_error(pTk, "line start location already fixed")
    return
  }
  if pObj.bClose {
    p.pik_error(pTk, "polygon is closed")
    return
  }
  if p.nTPath>1 {
    var dx PNum = pPt.x - p.aTPath[0].x
    var dy PNum = pPt.y - p.aTPath[0].y
    for i:=1; i<p.nTPath; i++ {
      p.aTPath[i].x += dx
      p.aTPath[i].y += dy
    }
  }
  p.aTPath[0] = *pPt
  p.mTPath = 3
  pObj.mProp |= A_FROM
  pObj.pFrom = p.pik_last_ref_object(pPt)
}

/* Set the "to" of an object
*/
func (p *Pik) pik_add_to(pObj *PObj, pTk *PToken, pPt *PPoint) {
  n := p.nTPath-1
  if !pObj.typ.isLine {
    p.pik_error(pTk, "use \"at\" to position this object")
    return
  }
  if pObj.bClose {
    p.pik_error(pTk, "polygon is closed")
    return
  }
  p.pik_reset_samepath()
  if n==0 || p.mTPath==3 || p.thenFlag {
    n = p.pik_next_rpath(pTk)
  }
  p.aTPath[n] = *pPt
  p.mTPath = 3
  pObj.pTo = p.pik_last_ref_object(pPt)
}

func (p *Pik) pik_close_path(pErr *PToken) {
  pObj := p.cur
  if p.nTPath<3 {
    p.pik_error(pErr,
      "need at least 3 vertexes in order to close the polygon")
    return
  }
  if pObj.bClose {
    p.pik_error(pErr, "polygon already closed")
    return
  }
  pObj.bClose = true
}

/* Lower the layer of the current object so that it is behind the
** given object.
*/
func (p *Pik) pik_behind(pOther *PObj) {
  pObj := p.cur
  if p.nErr==0 && pObj.iLayer>=pOther.iLayer {
    pObj.iLayer = pOther.iLayer - 1
  }
}


/* Set the "at" of an object
*/
func (p *Pik) pik_set_at(pEdge *PToken, pAt *PPoint, pErrTok *PToken) {
  eDirToCp := []uint8{CP_E, CP_S, CP_W, CP_N}
  if p.nErr != 0 { return }
  pObj := p.cur

  if pObj.typ.isLine {
    p.pik_error(pErrTok, "use \"from\" and \"to\" to position this object")
    return
  }
  if pObj.mProp&A_AT != 0 {
    p.pik_error(pErrTok, "location fixed by prior \"at\"")
    return
  }
  pObj.mProp |= A_AT
  pObj.eWith = CP_C
  if pEdge != nil {
    pObj.eWith = pEdge.eEdge
  }
  if pObj.eWith>=CP_END {
    dir := (pObj.inDir+2) % 4
    if pObj.eWith == CP_END {
      dir = pObj.outDir
    }
    pObj.eWith = eDirToCp[int(dir)]
  }
  pObj.with = *pAt
}

/*
** Try to add a text attribute to an object
*/
func (p *Pik) pik_add_txt(pTxt *PToken, iPos int16) {
  pObj := p.cur
  if int(pObj.nTxt) >= len(pObj.aTxt) {
    p.pik_error(pTxt, "too many text terms")
    return
  }
  pT := &pObj.aTxt[pObj.nTxt]
  pObj.nTxt++
  *pT = *pTxt
  pT.eCode = iPos
}

/* Merge "text-position" flags
*/
  func pik_text_position(iPrev int, pFlag *PToken) int {
    iRes := iPrev
    switch pFlag.eType {
    case T_LJUST:    iRes = (iRes&^TP_JMASK) | TP_LJUST
    case T_RJUST:    iRes = (iRes&^TP_JMASK) | TP_RJUST
    case T_ABOVE:    iRes = (iRes&^TP_VMASK) | TP_ABOVE
    case T_CENTER:   iRes = (iRes&^TP_VMASK) | TP_CENTER
    case T_BELOW:    iRes = (iRes&^TP_VMASK) | TP_BELOW
    case T_ITALIC:   iRes |= TP_ITALIC
    case T_BOLD:     iRes |= TP_BOLD
    case T_MONO:     iRes |= TP_MONO
    case T_ALIGNED:  iRes |= TP_ALIGN
    case T_BIG:      if iRes&TP_BIG != 0 { iRes |= TP_XTRA }  else {iRes = (iRes &^TP_SZMASK)|TP_BIG }
    case T_SMALL:    if iRes&TP_SMALL != 0 { iRes |= TP_XTRA } else { iRes = (iRes &^TP_SZMASK)|TP_SMALL }
  }
  return iRes
}

/*
** Table of scale-factor estimates for variable-width characters.
** Actual character widths vary by font.  These numbers are only
** guesses.  And this table only provides data for ASCII.
**
** 100 means normal width.
*/
var awChar = []byte{
  /* Skip initial 32 control characters */
  /* ' ' */  45,
  /* '!' */  55,
  /* '"' */  62,
  /* '#' */  115,
  /* '$' */  90,
  /* '%' */  132,
  /* '&' */  125,
  /* '\''*/  40,

  /* '(' */  55,
  /* ')' */  55,
  /* '*' */  71,
  /* '+' */  115,
  /* ',' */  45,
  /* '-' */  48,
  /* '.' */  45,
  /* '/' */  50,

  /* '0' */  91,
  /* '1' */  91,
  /* '2' */  91,
  /* '3' */  91,
  /* '4' */  91,
  /* '5' */  91,
  /* '6' */  91,
  /* '7' */  91,

  /* '8' */  91,
  /* '9' */  91,
  /* ':' */  50,
  /* ';' */  50,
  /* '<' */ 120,
  /* '=' */ 120,
  /* '>' */ 120,
  /* '?' */  78,

  /* '@' */ 142,
  /* 'A' */ 102,
  /* 'B' */ 105,
  /* 'C' */ 110,
  /* 'D' */ 115,
  /* 'E' */ 105,
  /* 'F' */  98,
  /* 'G' */ 105,

  /* 'H' */ 125,
  /* 'I' */  58,
  /* 'J' */  58,
  /* 'K' */ 107,
  /* 'L' */  95,
  /* 'M' */ 145,
  /* 'N' */ 125,
  /* 'O' */ 115,

  /* 'P' */  95,
  /* 'Q' */ 115,
  /* 'R' */ 107,
  /* 'S' */  95,
  /* 'T' */  97,
  /* 'U' */ 118,
  /* 'V' */ 102,
  /* 'W' */ 150,

  /* 'X' */ 100,
  /* 'Y' */  93,
  /* 'Z' */ 100,
  /* '[' */  58,
  /* '\\'*/  50,
  /* ']' */  58,
  /* '^' */ 119,
  /* '_' */  72,

  /* '`' */  72,
  /* 'a' */  86,
  /* 'b' */  92,
  /* 'c' */  80,
  /* 'd' */  92,
  /* 'e' */  85,
  /* 'f' */  52,
  /* 'g' */  92,

  /* 'h' */  92,
  /* 'i' */  47,
  /* 'j' */  47,
  /* 'k' */  88,
  /* 'l' */  48,
  /* 'm' */ 135,
  /* 'n' */  92,
  /* 'o' */  86,

  /* 'p' */  92,
  /* 'q' */  92,
  /* 'r' */  69,
  /* 's' */  75,
  /* 't' */  58,
  /* 'u' */  92,
  /* 'v' */  80,
  /* 'w' */ 121,

  /* 'x' */  81,
  /* 'y' */  80,
  /* 'z' */  76,
  /* '{' */  91,
  /* '|'*/   49,
  /* '}' */  91,
  /* '~' */ 118,
}

/* Return an estimate of the width of the displayed characters
** in a character string.  The returned value is 100 times the
** average character width.
**
** Omit "\" used to escape characters.  And count entities like
** "&lt;" as a single character.  Multi-byte UTF8 characters count
** as a single character.
**
** Unless using a monospaced font, attempt to scale the answer by
** the actual characters seen.  Wide characters count more than
** narrow characters. But the widths are only guesses.
*/
func pik_text_length(pToken PToken, isMonospace bool) int {
  const stdAvg, monoAvg = 100, 82
  n := pToken.n
  z := pToken.z
  cnt := 0
  for j:=1; j<n-1; j++ {
    c := z[j]
    if c=='\\' && z[j+1]!='&' {
      j++
      c = z[j]
    } else if c=='&' {
      var k int
      for k=j+1; k<j+7 && z[k]!=0 && z[k]!=';'; k++ {}
      if z[k]==';' { j = k }
      if isMonospace {
        cnt += monoAvg * 3 / 2
      } else {
        cnt += stdAvg * 3 / 2
      }
      continue
    }
    if (c & 0xc0)==0xc0 {
      for j+1<n-1 && (z[j+1]&0xc0)==0x80 { j++ }
      if isMonospace {
        cnt += monoAvg
      } else {
        cnt += stdAvg
      }
      continue
    }
    if isMonospace {
      cnt += monoAvg
    } else if c>=0x20 && c<=0x7e {
      cnt += int(awChar[int(c-0x20)])
    } else {
      cnt += stdAvg
    }
  }
  return cnt
}

/* Adjust the width, height, and/or radius of the object so that
** it fits around the text that has been added so far.
**
**    (1) Only text specified prior to this attribute is considered.
**    (2) The text size is estimated based on the charht and charwid
**        variable settings.
**    (3) The fitted attributes can be changed again after this
**        attribute, for example using "width 110%" if this auto-fit
**        underestimates the text size.
**    (4) Previously set attributes will not be altered.  In other words,
**        "width 1in fit" might cause the height to change, but the
**        width is now set.
**    (5) This only works for attributes that have an xFit method.
**
** The eWhich parameter is:
**
**    1:   Fit horizontally only
**    2:   Fit vertically only
**    3:   Fit both ways
*/
func (p *Pik) pik_size_to_fit(pObj *PObj, pFit *PToken, eWhich int) {
  var w, h PNum
  var bbox PBox

  if p.nErr != 0 { return }
  if pObj == nil { pObj = p.cur }

  if pObj.nTxt==0 {
    (*Pik)(nil).pik_error(pFit, "no text to fit to")
    return
  }
  if pObj.typ.xFit==nil { return }
  pik_bbox_init(&bbox)
  p.pik_compute_layout_settings()
  p.pik_append_txt(pObj, &bbox)
  if eWhich&1 != 0 || pObj.bAltAutoFit {
    w = (bbox.ne.x - bbox.sw.x) + p.charWidth
  }
  if eWhich&2 != 0 || pObj.bAltAutoFit {
    var h1, h2 PNum
    h1 = bbox.ne.y - pObj.ptAt.y
    h2 = pObj.ptAt.y - bbox.sw.y
    hmax := h1
    if h1 < h2 {
      hmax = h2
    }
    h = 2.0*hmax + 0.5*p.charHeight
  } else {
    h = 0
  }
  pObj.typ.xFit(p, pObj, w, h)
  pObj.mProp |= A_FIT
}

/* Set a local variable name to "val".
**
** The name might be a built-in variable or a color name.  In either case,
** a new application-defined variable is set.  Since app-defined variables
** are searched first, this will override any built-in variables.
*/
func (p *Pik) pik_set_var(pId *PToken, val PNum, pOp *PToken) {
  pVar := p.pVar
  for pVar != nil {
    if pik_token_eq(pId,pVar.zName)==0 {
      break
    }
    pVar = pVar.pNext
  }
  if pVar==nil {
    pVar = &PVar{
      zName: pId.String(),
      pNext: p.pVar,
      val: p.pik_value(pId.String(), nil),
    }
    p.pVar = pVar
  }
  switch pOp.eCode {
    case T_PLUS:  pVar.val += val
    case T_STAR:  pVar.val *= val
    case T_MINUS: pVar.val -= val
    case T_SLASH:
      if val==0.0 {
        p.pik_error(pOp, "division by zero")
      }else{
        pVar.val /= val
      }
    default:      pVar.val = val
  }
  p.bLayoutVars = false  /* Clear the layout setting cache */
}

/*
** Round a PNum into the nearest integer
*/
func pik_round(v PNum) int {
  switch {
  case math.IsNaN(v):
    return 0
  case v < -2147483647:
    return (-2147483647-1)
  case v >= 2147483647:
    return 2147483647
  default:
    return int(v+math.Copysign(1e-15,v))
  }
}

/*
** Search for the variable named z[0..n-1] in:
**
**   * Application defined variables
**   * Built-in variables
**
** Return the value of the variable if found.  If not found
** return 0.0.  Also if pMiss is not NULL, then set it to 1
** if not found.
**
** This routine is a subroutine to pik_get_var().  But it is also
** used by object implementations to look up (possibly overwritten)
** values for built-in variables like "boxwid".
*/
func (p *Pik) pik_value(z string, pMiss *bool) PNum{
  for pVar:=p.pVar ; pVar != nil; pVar=pVar.pNext {
    if pVar.zName == z {
      return pVar.val
    }
  }
  first := 0
  last := len(aBuiltin)-1
  for first<=last {
    mid := (first+last)/2
    zName := aBuiltin[mid].zName

    if zName == z {
      return aBuiltin[mid].val
    } else if z > zName {
      first = mid+1
    } else {
      last = mid-1
    }
  }
  if pMiss != nil { *pMiss = true }
  return 0.0
}

func (p *Pik) pik_value_int(z string, pMiss *bool) int{
  return pik_round(p.pik_value(z,pMiss))
}

/*
** Look up a color-name.  Unlike other names in this program, the
** color-names are not case sensitive.  So "DarkBlue" and "darkblue"
** and "DARKBLUE" all find the same value (139).
**
** If not found, return -99.0.  Also post an error if p!=NULL.
**
** Special color names "None" and "Off" return -1.0 without causing
** an error.
*/
func (p *Pik) pik_lookup_color(pId *PToken) PNum {
  first := 0
  last := len(aColor)-1
  zId := strings.ToLower(pId.String())
  for first<=last {
    mid := (first+last)/2
    zClr := strings.ToLower(aColor[mid].zName)
    c := strings.Compare(zId, zClr)

    if c==0 { return PNum(aColor[mid].val) }
    if c>0 {
      first = mid+1
    }else{
      last = mid-1
    }
  }
  if p != nil { p.pik_error(pId, "not a known color name") }
  return -99.0
}

/* Get the value of a variable.
**
** Search in order:
**
**    *  Application defined variables
**    *  Built-in variables
**    *  Color names
**
** If no such variable is found, throw an error.
*/
func (p *Pik) pik_get_var(pId *PToken) PNum {
  miss := false
  v := p.pik_value(pId.String(), &miss)
  if !miss { return v }
  v = (*Pik)(nil).pik_lookup_color(pId)
  if v>-90.0 { return v }
  p.pik_error(pId,"no such variable")
  return 0.0
}

/* Convert a T_NTH token (ex: "2nd", "5th"} into a numeric value and
 ** return that value.  Throw an error if the value is too big.
 */
func (p *Pik) pik_nth_value(pNth *PToken) int16 {
  s := pNth.String()
  if s == "first" {
    return 1
  }

  i, err := strconv.Atoi(s[:len(s)-2])
  if err != nil {
    p.pik_error(pNth, "value can't be parsed as a number")
  }
  if i>1000 {
    p.pik_error(pNth, "value too big - max '1000th'")
    i = 1
  }
  return int16(i)
}

/* Search for the NTH object.
**
** If pBasis is not NULL then it should be a [] object.  Use the
** sublist of that [] object for the search.  If pBasis is not a []
** object, then throw an error.
**
** The pNth token describes the N-th search.  The pNth.eCode value
** is one more than the number of items to skip.  It is negative
** to search backwards.  If pNth.eType==T_ID, then it is the name
** of a class to search for.  If pNth.eType==T_LB, then
** search for a [] object.  If pNth.eType==T_LAST, then search for
** any type.
**
** Raise an error if the item is not found.
*/
func (p *Pik) pik_find_nth(pBasis *PObj, pNth *PToken) *PObj {
  var pList PList
  var pClass *PClass
  if pBasis==nil {
    pList = p.list
  }else{
    pList = pBasis.pSublist
  }
  if pList==nil {
    p.pik_error(pNth, "no such object")
    return nil
  }
  if pNth.eType==T_LAST {
    pClass = nil
  } else if pNth.eType==T_LB {
    pClass = &sublistClass
  } else {
    pClass = pik_find_class(pNth)
    if pClass==nil {
      (*Pik)(nil).pik_error(pNth, "no such object type")
      return nil
    }
  }
  n := pNth.eCode
  if n<0 {
    for i:=len(pList)-1; i>=0; i-- {
      pObj := pList[i]
      if pClass != nil && pObj.typ!=pClass { continue }
      n++
      if n==0 { return pObj }
    }
  } else {
    for i:=0; i<len(pList); i++ {
      pObj := pList[i]
      if pClass != nil && pObj.typ!=pClass { continue }
      n--
      if n==0 { return pObj }
    }
  }
  p.pik_error(pNth, "no such object")
  return nil
}

/* Search for an object by name.
**
** Search in pBasis.pSublist if pBasis is not NULL.  If pBasis is NULL
** then search in p.list.
*/
func (p *Pik) pik_find_byname(pBasis *PObj, pName *PToken) *PObj {
  var pList PList
  if pBasis==nil {
    pList = p.list
  } else {
    pList = pBasis.pSublist
  }
  if pList==nil {
    p.pik_error(pName, "no such object")
    return nil
  }
  /* First look explicitly tagged objects */
  for i:=len(pList)-1; i>=0; i-- {
    pObj := pList[i]
    if pObj.zName != "" && pik_token_eq(pName,pObj.zName)==0 {
      p.lastRef = pObj
      return pObj
    }
  }
  /* If not found, do a second pass looking for any object containing
  ** text which exactly matches pName */
  for i:=len(pList)-1; i>=0; i-- {
    pObj := pList[i]
    for j:=0; j<int(pObj.nTxt); j++ {
      t := pObj.aTxt[j].n
      if t==pName.n+2 && bytesEq(pObj.aTxt[j].z[1:t-1], pName.z[:pName.n]) {
        p.lastRef = pObj
        return pObj
      }
    }
  }
  p.pik_error(pName, "no such object")
  return nil
}

/* Change most of the settings for the current object to be the
** same as the pOther object, or the most recent object of the same
** type if pOther is NULL.
*/
func (p *Pik) pik_same(pOther *PObj, pErrTok *PToken) {
  pObj := p.cur
  if p.nErr != 0 { return }
  if pOther==nil {
    var i int
    for i = len(p.list)-1; i >= 0; i-- {
      pOther = p.list[i]
      if pOther.typ==pObj.typ { break }
    }
    if i<0 {
      p.pik_error(pErrTok, "no prior objects of the same type")
      return
    }
  }
  if pOther.nPath != 0 && pObj.typ.isLine {
    var dx, dy PNum
    dx = p.aTPath[0].x - pOther.aPath[0].x
    dy = p.aTPath[0].y - pOther.aPath[0].y
    for i:=1; i<pOther.nPath; i++ {
      p.aTPath[i].x = pOther.aPath[i].x + dx
      p.aTPath[i].y = pOther.aPath[i].y + dy
    }
    p.nTPath = pOther.nPath
    p.mTPath = 3
    p.samePath = true
  }
  if !pObj.typ.isLine {
    pObj.w = pOther.w
    pObj.h = pOther.h
  }
  pObj.rad = pOther.rad
  pObj.sw = pOther.sw
  pObj.dashed = pOther.dashed
  pObj.dotted = pOther.dotted
  pObj.fill = pOther.fill
  pObj.color = pOther.color
  pObj.cw = pOther.cw
  pObj.larrow = pOther.larrow
  pObj.rarrow = pOther.rarrow
  pObj.bClose = pOther.bClose
  pObj.bChop = pOther.bChop
  pObj.iLayer = pOther.iLayer
}


/* Return a "Place" associated with object pObj.  If pEdge is NULL
** return the center of the object.  Otherwise, return the corner
** described by pEdge.
*/
func (p *Pik) pik_place_of_elem(pObj *PObj, pEdge *PToken) PPoint {
  pt := PPoint{}
  var pClass *PClass
  if pObj==nil { return pt }
  if pEdge==nil {
    return pObj.ptAt
  }
  pClass = pObj.typ
  if pEdge.eType==T_EDGEPT || (pEdge.eEdge>0 && pEdge.eEdge<CP_END) {
    pt = pClass.xOffset(p, pObj, pEdge.eEdge)
    pt.x += pObj.ptAt.x
    pt.y += pObj.ptAt.y
    return pt
  }
  if pEdge.eType==T_START {
    return pObj.ptEnter
  }else{
    return pObj.ptExit
  }
}

/* Do a linear interpolation of two positions.
*/
func pik_position_between(x PNum, p1 PPoint, p2 PPoint) PPoint {
  var out PPoint
  out.x = p2.x*x + p1.x*(1.0 - x)
  out.y = p2.y*x + p1.y*(1.0 - x)
  return out
}

/* Compute the position that is dist away from pt at an heading angle of r
**
** The angle is a compass heading in degrees.  North is 0 (or 360).
** East is 90.  South is 180.  West is 270.  And so forth.
*/
func pik_position_at_angle(dist PNum, r PNum, pt PPoint)  PPoint {
  r *= 0.017453292519943295769  /* degrees to radians */
  pt.x += dist*math.Sin(r)
  pt.y += dist*math.Cos(r)
  return pt
}

/* Compute the position that is dist away at a compass point
*/
 func pik_position_at_hdg(dist PNum, pD *PToken, pt PPoint) PPoint {
  return pik_position_at_angle(dist, pik_hdg_angle[pD.eEdge], pt)
}

/* Return the coordinates for the n-th vertex of a line.
*/
func (p *Pik) pik_nth_vertex(pNth *PToken, pErr *PToken, pObj *PObj) PPoint {
  var n int
  zero := PPoint{}
  if p.nErr != 0 || pObj==nil { return p.aTPath[0] }
  if !pObj.typ.isLine {
    p.pik_error(pErr, "object is not a line")
    return zero
  }
  n, err := strconv.Atoi(string(pNth.z[:pNth.n-2]))
  if err != nil || n<1 || n>pObj.nPath {
    p.pik_error(pNth, "no such vertex")
    return zero
  }
  return pObj.aPath[n-1]
}

/* Return the value of a property of an object.
*/
func pik_property_of(pObj *PObj, pProp *PToken) PNum {
  var v PNum
  if pObj != nil {
    switch pProp.eType {
      case T_HEIGHT:    v = pObj.h
      case T_WIDTH:     v = pObj.w
      case T_RADIUS:    v = pObj.rad
      case T_DIAMETER:  v = pObj.rad*2.0
      case T_THICKNESS: v = pObj.sw
      case T_DASHED:    v = pObj.dashed
      case T_DOTTED:    v = pObj.dotted
      case T_FILL:      v = pObj.fill
      case T_COLOR:     v = pObj.color
      case T_X:         v = pObj.ptAt.x
      case T_Y:         v = pObj.ptAt.y
      case T_TOP:       v = pObj.bbox.ne.y
      case T_BOTTOM:    v = pObj.bbox.sw.y
      case T_LEFT:      v = pObj.bbox.sw.x
      case T_RIGHT:     v = pObj.bbox.ne.x
    }
  }
  return v
}

/* Compute one of the built-in functions
*/
func (p *Pik) pik_func(pFunc *PToken, x PNum, y PNum) PNum {
  var v PNum
  switch pFunc.eCode {
  case FN_ABS:  v = x; if v < 0 { v = -x }
  case FN_COS:  v = math.Cos(x)
  case FN_INT:  v = math.Trunc(x)
  case FN_SIN:  v = math.Sin(x)
  case FN_SQRT:
    if x<0.0 {
      p.pik_error(pFunc, "sqrt of negative value")
      v = 0.0
    }else{
      v = math.Sqrt(x)
    }
  case FN_MAX:  if x>y { v=x } else { v=y }
  case FN_MIN:  if x<y { v=x } else { v=y }
  default:      v = 0.0
  }
  return v
}

/* Attach a name to an object
*/
func (p *Pik) pik_elem_setname(pObj *PObj, pName *PToken){
  if pObj==nil {return}
  if pName==nil {return}
  pObj.zName = pName.String()
}

/*
** Search for object located at *pCenter that has an xChop method and
** that does not enclose point pOther.
**
** Return a pointer to the object, or NULL if not found.
*/
func pik_find_chopper(pList PList, pCenter *PPoint, pOther *PPoint) *PObj {
  if pList==nil { return nil }
  for i:=len(pList)-1; i>=0; i-- {
    pObj := pList[i]
    if pObj.typ.xChop!=nil &&
      pObj.ptAt.x==pCenter.x &&
      pObj.ptAt.y==pCenter.y &&
      !pik_bbox_contains_point(&pObj.bbox, pOther) {
      return pObj
    } else if pObj.pSublist != nil {
      pObj = pik_find_chopper(pObj.pSublist,pCenter,pOther)
      if pObj != nil { return pObj }
    }
  }
  return nil
}

/*
** There is a line traveling from pFrom to pTo.
**
** If pObj is not null and is a choppable object, then chop at
** the boundary of pObj - where the line crosses the boundary
** of pObj.
**
** If pObj is NULL or has no xChop method, then search for some
** other object centered at pTo that is choppable and use it
** instead.
*/
func (p *Pik) pik_autochop(pFrom *PPoint, pTo *PPoint, pObj *PObj) {
  if pObj==nil || pObj.typ.xChop==nil {
    pObj = pik_find_chopper(p.list, pTo, pFrom)
  }
  if pObj != nil {
    *pTo = pObj.typ.xChop(p, pObj, pFrom)
  }
}

/* This routine runs after all attributes have been received
** on an object.
*/
func (p *Pik) pik_after_adding_attributes(pObj *PObj) {
  if p.nErr != 0 { return }

  /* Position block objects */
  if !pObj.typ.isLine {
    /* A height or width less than or equal to zero means "autofit".
    ** Change the height or width to be big enough to contain the text,
    */
    if pObj.h<=0.0 {
      if pObj.nTxt==0 {
        pObj.h = 0.0
      } else if pObj.w<=0.0 {
        p.pik_size_to_fit(pObj, &pObj.errTok, 3)
      } else {
        p.pik_size_to_fit(pObj, &pObj.errTok, 2)
      }
    }
    if pObj.w<=0.0 {
      if pObj.nTxt==0 {
        pObj.w = 0.0
      } else {
        p.pik_size_to_fit(pObj, &pObj.errTok, 1)
      }
    }
    ofst := p.pik_elem_offset(pObj, pObj.eWith)
    var dx PNum = (pObj.with.x - ofst.x) - pObj.ptAt.x
    var dy PNum = (pObj.with.y - ofst.y) - pObj.ptAt.y
    if dx!=0 || dy!=0 {
      pik_elem_move(pObj, dx, dy)
    }
  }

  /* For a line object with no movement specified, a single movement
  ** of the default length in the current direction
  */
  if pObj.typ.isLine && p.nTPath<2 {
    p.pik_next_rpath(nil)
    assert( p.nTPath==2, fmt.Sprintf("want p.nTPath==2; got %d", p.nTPath))
    switch pObj.inDir {
      default:        p.aTPath[1].x += pObj.w
      case DIR_DOWN:  p.aTPath[1].y -= pObj.h
      case DIR_LEFT:  p.aTPath[1].x -= pObj.w
      case DIR_UP:    p.aTPath[1].y += pObj.h
    }
    if pObj.typ.zName=="arc" {
      add := uint8(3)
      if pObj.cw {
        add = 1
      }
      pObj.outDir = (pObj.inDir + add)%4
      p.eDir = pObj.outDir
      switch pObj.outDir {
        default:        p.aTPath[1].x += pObj.w
        case DIR_DOWN:  p.aTPath[1].y -= pObj.h
        case DIR_LEFT:  p.aTPath[1].x -= pObj.w
        case DIR_UP:    p.aTPath[1].y += pObj.h
      }
    }
  }

  /* Initialize the bounding box prior to running xCheck */
  pik_bbox_init(&pObj.bbox)

  /* Run object-specific code */
  if pObj.typ.xCheck!=nil {
    pObj.typ.xCheck(p,pObj)
    if p.nErr != 0 { return }
  }

  /* Compute final bounding box, entry and exit points, center
  ** point (ptAt) and path for the object
  */
  if pObj.typ.isLine {
    pObj.aPath = make([]PPoint, p.nTPath)
    pObj.nPath = p.nTPath
    copy(pObj.aPath, p.aTPath[:p.nTPath])

    /* "chop" processing:
    ** If the line goes to the center of an object with an
    ** xChop method, then use the xChop method to trim the line.
    */
    if pObj.bChop && pObj.nPath>=2 {
      n := pObj.nPath
      p.pik_autochop(&pObj.aPath[n-2], &pObj.aPath[n-1], pObj.pTo)
      p.pik_autochop(&pObj.aPath[1], &pObj.aPath[0], pObj.pFrom)
    }

    pObj.ptEnter = pObj.aPath[0]
    pObj.ptExit = pObj.aPath[pObj.nPath-1]

    /* Compute the center of the line based on the bounding box over
    ** the vertexes.  This is a difference from PIC.  In Pikchr, the
    ** center of a line is the center of its bounding box. In PIC, the
    ** center of a line is halfway between its .start and .end.  For
    ** straight lines, this is the same point, but for multi-segment
    ** lines the result is usually diferent */
    for i:=0; i<pObj.nPath; i++ {
      pik_bbox_add_xy(&pObj.bbox, pObj.aPath[i].x, pObj.aPath[i].y)
    }
    pObj.ptAt.x = (pObj.bbox.ne.x + pObj.bbox.sw.x)/2.0
    pObj.ptAt.y = (pObj.bbox.ne.y + pObj.bbox.sw.y)/2.0

    /* Reset the width and height of the object to be the width and height
    ** of the bounding box over vertexes */
    pObj.w = pObj.bbox.ne.x - pObj.bbox.sw.x
    pObj.h = pObj.bbox.ne.y - pObj.bbox.sw.y

    /* If this is a polygon (if it has the "close" attribute), then
    ** adjust the exit point */
    if pObj.bClose {
      /* For "closed" lines, the .end is one of the .e, .s, .w, or .n
      ** points of the bounding box, as with block objects. */
      pik_elem_set_exit(pObj, pObj.inDir)
    }
  } else {
    var w2 PNum = pObj.w/2.0
    var h2 PNum = pObj.h/2.0
    pObj.ptEnter = pObj.ptAt
    pObj.ptExit = pObj.ptAt
    switch pObj.inDir {
      default:         pObj.ptEnter.x -= w2
      case DIR_LEFT:   pObj.ptEnter.x += w2
      case DIR_UP:     pObj.ptEnter.y -= h2
      case DIR_DOWN:   pObj.ptEnter.y += h2
    }
    switch pObj.outDir {
      default:         pObj.ptExit.x += w2
      case DIR_LEFT:   pObj.ptExit.x -= w2
      case DIR_UP:     pObj.ptExit.y += h2
      case DIR_DOWN:   pObj.ptExit.y -= h2
    }
    pik_bbox_add_xy(&pObj.bbox, pObj.ptAt.x - w2, pObj.ptAt.y - h2)
    pik_bbox_add_xy(&pObj.bbox, pObj.ptAt.x + w2, pObj.ptAt.y + h2)
  }
  p.eDir = pObj.outDir
}

/* Show basic information about each object as a comment in the
** generated HTML.  Used for testing and debugging.  Activated
** by the (undocumented) "debug = 1;"
** command.
*/
func (p *Pik) pik_elem_render(pObj *PObj) {
  var zDir string
  if pObj==nil { return }
  p.pik_append("<!-- ")
  if pObj.zName != "" {
    p.pik_append_text(pObj.zName, 0)
    p.pik_append(": ")
  }
  p.pik_append_text(pObj.typ.zName, 0)
  if pObj.nTxt != 0 {
    p.pik_append(" \"")
    z := pObj.aTxt[0]
    p.pik_append_text(string(z.z[1:z.n-1]), 1)
    p.pik_append("\"")
  }
  p.pik_append_num(" w=", pObj.w)
  p.pik_append_num(" h=", pObj.h)
  p.pik_append_point(" center=", &pObj.ptAt)
  p.pik_append_point(" enter=", &pObj.ptEnter)
  switch pObj.outDir {
    default:        zDir = " right"
    case DIR_LEFT:  zDir = " left"
    case DIR_UP:    zDir = " up"
    case DIR_DOWN:  zDir = " down"
  }
  p.pik_append_point(" exit=", &pObj.ptExit)
  p.pik_append(zDir)
  p.pik_append(" -->\n")
}

/* Render a list of objects
*/
func (p *Pik) pik_elist_render(pList PList) {
  var iNextLayer, iThisLayer int
  bMoreToDo := true
  mDebug := p.pik_value_int("debug", nil)
  for bMoreToDo {
    bMoreToDo = false
    iThisLayer = iNextLayer
    iNextLayer = 0x7fffffff
    for i:=0; i<len(pList); i++ {
      pObj := pList[i]
      if pObj.iLayer>iThisLayer {
        if pObj.iLayer<iNextLayer { iNextLayer = pObj.iLayer }
        bMoreToDo = true
        continue /* Defer until another round */
      } else if pObj.iLayer<iThisLayer {
        continue
      }
      if mDebug&1 != 0 { p.pik_elem_render(pObj) }
      xRender := pObj.typ.xRender
      if xRender != nil {
        xRender(p, pObj)
      }
      if pObj.pSublist != nil {
        p.pik_elist_render(pObj.pSublist)
      }
    }
  }

  /* If the color_debug_label value is defined, then go through
  ** and paint a dot at every label location */
  miss := false
  var colorLabel PNum = p.pik_value("debug_label_color", &miss)
  if !miss && colorLabel>=0.0 {
    dot := PObj{}
    dot.typ = &noopClass
    dot.rad = 0.015
    dot.sw = 0.015
    dot.fill = colorLabel
    dot.color = colorLabel
    dot.nTxt = 1
    dot.aTxt[0].eCode = TP_ABOVE
    for i:=0; i<len(pList); i++ {
      pObj := pList[i]
      if pObj.zName == "" { continue }
      dot.ptAt = pObj.ptAt
      dot.aTxt[0].z = []byte(pObj.zName)
      dot.aTxt[0].n = len(dot.aTxt[0].z)
      dotRender(p, &dot)
    }
  }
}

/* Add all objects of the list pList to the bounding box
*/
func (p *Pik) pik_bbox_add_elist(pList PList, wArrow PNum) {
  for i:=0; i<len(pList); i++ {
    pObj := pList[i]
    if pObj.sw>=0.0 { pik_bbox_addbox(&p.bbox, &pObj.bbox) }
    p.pik_append_txt(pObj, &p.bbox)
    if pObj.pSublist != nil { p.pik_bbox_add_elist(pObj.pSublist, wArrow) }

    /* Expand the bounding box to account for arrowheads on lines */
    if pObj.typ.isLine && pObj.nPath>0 {
      if pObj.larrow {
        pik_bbox_addellipse(&p.bbox, pObj.aPath[0].x, pObj.aPath[0].y,
                            wArrow, wArrow)
      }
      if pObj.rarrow {
        j := pObj.nPath-1
        pik_bbox_addellipse(&p.bbox, pObj.aPath[j].x, pObj.aPath[j].y,
                            wArrow, wArrow)
      }
    }
  }
}

/* Recompute key layout parameters from variables. */
func (p *Pik) pik_compute_layout_settings() {
  var thickness PNum  /* Line thickness */
  var wArrow PNum     /* Width of arrowheads */

  /* Set up rendering parameters */
  if p.bLayoutVars { return }
  thickness = p.pik_value("thickness",nil)
  if thickness<=0.01 { thickness = 0.01 }
  wArrow = 0.5*p.pik_value("arrowwid",nil)
  p.wArrow = wArrow/thickness
  p.hArrow = p.pik_value("arrowht",nil)/thickness
  p.fontScale = p.pik_value("fontscale",nil)
  if p.fontScale<=0.0 { p.fontScale = 1.0 }
  p.rScale = 144.0
  p.charWidth = p.pik_value("charwid",nil)*p.fontScale
  p.charHeight = p.pik_value("charht",nil)*p.fontScale
  p.bLayoutVars = true
}

/* Render a list of objects.  Write the SVG into p.zOut.
** Delete the input object_list before returnning.
*/
func (p *Pik) pik_render(pList PList) {
  if pList==nil {return}
  if p.nErr==0 {
    var (
      thickness PNum  /* Stroke width */
      margin PNum     /* Extra bounding box margin */
      w, h PNum       /* Drawing width and height */
      wArrow PNum
      pikScale PNum     /* Value of the "scale" variable */
    )

    /* Set up rendering parameters */
    p.pik_compute_layout_settings()
    thickness = p.pik_value("thickness",nil)
    if thickness<=0.01 { thickness = 0.01 }
    margin = p.pik_value("margin",nil)
    margin += thickness
    wArrow = p.wArrow*thickness
    miss := false
    p.fgcolor = p.pik_value_int("fgcolor",&miss)
    if miss {
      var t PToken
      t.z = []byte("fgcolor")
      t.n = 7
      p.fgcolor = pik_round((*Pik)(nil).pik_lookup_color(&t))
    }
    miss = false
    p.bgcolor = p.pik_value_int("bgcolor",&miss)
    if miss {
      var t PToken
      t.z = []byte("bgcolor")
      t.n = 7
      p.bgcolor = pik_round((*Pik)(nil).pik_lookup_color(&t))
    }

    /* Compute a bounding box over all objects so that we can know
    ** how big to declare the SVG canvas */
    pik_bbox_init(&p.bbox)
    p.pik_bbox_add_elist(pList, wArrow)

    /* Expand the bounding box slightly to account for line thickness
    ** and the optional "margin = EXPR" setting. */
    p.bbox.ne.x += margin + p.pik_value("rightmargin",nil)
    p.bbox.ne.y += margin + p.pik_value("topmargin",nil)
    p.bbox.sw.x -= margin + p.pik_value("leftmargin",nil)
    p.bbox.sw.y -= margin + p.pik_value("bottommargin",nil)

    /* Output the SVG */
    p.pik_append("<svg xmlns='http://www.w3.org/2000/svg'" +
    " style='font-size:initial;'")
    if p.zClass != "" {
      p.pik_append(" class=\"")
      p.pik_append(p.zClass)
      p.pik_append("\"")
    }
    w = p.bbox.ne.x - p.bbox.sw.x
    h = p.bbox.ne.y - p.bbox.sw.y
    p.wSVG = pik_round(p.rScale*w)
    p.hSVG = pik_round(p.rScale*h)
    pikScale = p.pik_value("scale",nil)
    if pikScale>=0.001 && pikScale<=1000.0 &&
     (pikScale<0.99 || pikScale>1.01) {
      p.wSVG = pik_round(PNum(p.wSVG)*pikScale)
      p.hSVG = pik_round(PNum(p.hSVG)*pikScale)
      p.pik_append_num(" width=\"", PNum(p.wSVG))
      p.pik_append_num("\" height=\"", PNum(p.hSVG))
      p.pik_append("\"")
    }
    p.pik_append_dis(" viewBox=\"0 0 ",w,"")
    p.pik_append_dis(" ",h,"\"")
    p.pik_append(" data-pikchr-date=\"" + ManifestISODate + "\">\n")
    p.pik_elist_render(pList)
    p.pik_append("</svg>\n")
  }else{
    p.wSVG = -1
    p.hSVG = -1
  }
  p.pik_elist_free(&pList)
}



/*
** An array of this structure defines a list of keywords.
*/
type PikWord struct {
  zWord string /* Text of the keyword */
  //TODO(zellyn): do we need this?
  nChar uint8  /* Length of keyword text in bytes */
  eType uint8  /* Token code */
  eCode uint8  /* Extra code for the token */
  eEdge uint8  /* CP_* code for corner/edge keywords */
}

/*
** Keywords
*/
var pik_keywords = []PikWord{
  { "above",      5,   T_ABOVE,     0,         0        },
  { "abs",        3,   T_FUNC1,     FN_ABS,    0        },
  { "aligned",    7,   T_ALIGNED,   0,         0        },
  { "and",        3,   T_AND,       0,         0        },
  { "as",         2,   T_AS,        0,         0        },
  { "assert",     6,   T_ASSERT,    0,         0        },
  { "at",         2,   T_AT,        0,         0        },
  { "behind",     6,   T_BEHIND,    0,         0        },
  { "below",      5,   T_BELOW,     0,         0        },
  { "between",    7,   T_BETWEEN,   0,         0        },
  { "big",        3,   T_BIG,       0,         0        },
  { "bold",       4,   T_BOLD,      0,         0        },
  { "bot",        3,   T_EDGEPT,    0,         CP_S     },
  { "bottom",     6,   T_BOTTOM,    0,         CP_S     },
  { "c",          1,   T_EDGEPT,    0,         CP_C     },
  { "ccw",        3,   T_CCW,       0,         0        },
  { "center",     6,   T_CENTER,    0,         CP_C     },
  { "chop",       4,   T_CHOP,      0,         0        },
  { "close",      5,   T_CLOSE,     0,         0        },
  { "color",      5,   T_COLOR,     0,         0        },
  { "cos",        3,   T_FUNC1,     FN_COS,    0        },
  { "cw",         2,   T_CW,        0,         0        },
  { "dashed",     6,   T_DASHED,    0,         0        },
  { "define",     6,   T_DEFINE,    0,         0        },
  { "diameter",   8,   T_DIAMETER,  0,         0        },
  { "dist",       4,   T_DIST,      0,         0        },
  { "dotted",     6,   T_DOTTED,    0,         0        },
  { "down",       4,   T_DOWN,      DIR_DOWN,  0        },
  { "e",          1,   T_EDGEPT,    0,         CP_E     },
  { "east",       4,   T_EDGEPT,    0,         CP_E     },
  { "end",        3,   T_END,       0,         CP_END   },
  { "even",       4,   T_EVEN,      0,         0        },
  { "fill",       4,   T_FILL,      0,         0        },
  { "first",      5,   T_NTH,       0,         0        },
  { "fit",        3,   T_FIT,       0,         0        },
  { "from",       4,   T_FROM,      0,         0        },
  { "go",         2,   T_GO,        0,         0        },
  { "heading",    7,   T_HEADING,   0,         0        },
  { "height",     6,   T_HEIGHT,    0,         0        },
  { "ht",         2,   T_HEIGHT,    0,         0        },
  { "in",         2,   T_IN,        0,         0        },
  { "int",        3,   T_FUNC1,     FN_INT,    0        },
  { "invis",      5,   T_INVIS,     0,         0        },
  { "invisible",  9,   T_INVIS,     0,         0        },
  { "italic",     6,   T_ITALIC,    0,         0        },
  { "last",       4,   T_LAST,      0,         0        },
  { "left",       4,   T_LEFT,      DIR_LEFT,  CP_W     },
  { "ljust",      5,   T_LJUST,     0,         0        },
  { "max",        3,   T_FUNC2,     FN_MAX,    0        },
  { "min",        3,   T_FUNC2,     FN_MIN,    0        },
  { "mono",       4,   T_MONO,      0,         0        },
  { "monospace",  9,   T_MONO,      0,         0        },
  { "n",          1,   T_EDGEPT,    0,         CP_N     },
  { "ne",         2,   T_EDGEPT,    0,         CP_NE    },
  { "north",      5,   T_EDGEPT,    0,         CP_N     },
  { "nw",         2,   T_EDGEPT,    0,         CP_NW    },
  { "of",         2,   T_OF,        0,         0        },
  { "pikchr_date",11,  T_ISODATE,   0,         0,       },
  { "previous",   8,   T_LAST,      0,         0,       },
  { "print",      5,   T_PRINT,     0,         0        },
  { "rad",        3,   T_RADIUS,    0,         0        },
  { "radius",     6,   T_RADIUS,    0,         0        },
  { "right",      5,   T_RIGHT,     DIR_RIGHT, CP_E     },
  { "rjust",      5,   T_RJUST,     0,         0        },
  { "s",          1,   T_EDGEPT,    0,         CP_S     },
  { "same",       4,   T_SAME,      0,         0        },
  { "se",         2,   T_EDGEPT,    0,         CP_SE    },
  { "sin",        3,   T_FUNC1,     FN_SIN,    0        },
  { "small",      5,   T_SMALL,     0,         0        },
  { "solid",      5,   T_SOLID,     0,         0        },
  { "south",      5,   T_EDGEPT,    0,         CP_S     },
  { "sqrt",       4,   T_FUNC1,     FN_SQRT,   0        },
  { "start",      5,   T_START,     0,         CP_START },
  { "sw",         2,   T_EDGEPT,    0,         CP_SW    },
  { "t",          1,   T_TOP,       0,         CP_N     },
  { "the",        3,   T_THE,       0,         0        },
  { "then",       4,   T_THEN,      0,         0        },
  { "thick",      5,   T_THICK,     0,         0        },
  { "thickness",  9,   T_THICKNESS, 0,         0        },
  { "thin",       4,   T_THIN,      0,         0        },
  { "this",       4,   T_THIS,      0,         0        },
  { "to",         2,   T_TO,        0,         0        },
  { "top",        3,   T_TOP,       0,         CP_N     },
  { "until",      5,   T_UNTIL,     0,         0        },
  { "up",         2,   T_UP,        DIR_UP,    0        },
  { "vertex",     6,   T_VERTEX,    0,         0        },
  { "w",          1,   T_EDGEPT,    0,         CP_W     },
  { "way",        3,   T_WAY,       0,         0        },
  { "west",       4,   T_EDGEPT,    0,         CP_W     },
  { "wid",        3,   T_WIDTH,     0,         0        },
  { "width",      5,   T_WIDTH,     0,         0        },
  { "with",       4,   T_WITH,      0,         0        },
  { "x",          1,   T_X,         0,         0        },
  { "y",          1,   T_Y,         0,         0        },
}

/*
** Search a PikWordlist for the given keyword.  Return a pointer to the
** keyword entry found.  Or return 0 if not found.
*/
func pik_find_word(
  zIn string,              /* Word to search for */
  aList []PikWord,         /* List to search */
) *PikWord {
  first := 0
  last := len(aList) - 1
  for first<=last {
    mid := (first + last)/2
    c := strings.Compare(zIn, aList[mid].zWord)
    if c==0 {
      return &aList[mid]
    }
    if c<0 {
      last = mid-1
    } else {
      first = mid+1
    }
  }
  return nil
}

/*
** Set a symbolic debugger breakpoint on this routine to receive a
** breakpoint when the "#breakpoint" token is parsed.
*/
func pik_breakpoint(z []byte) {
  /* Prevent C compilers from optimizing out this routine. */
  if z[2]=='X' { os.Exit(1) }
}


var aEntity = []struct{
  eCode int            /* Corresponding token code */
  zEntity string       /* Name of the HTML entity */
}{
  { T_RARROW,  "&rarr;"           },   /* Same as . */
  { T_RARROW,  "&rightarrow;"     },   /* Same as . */
  { T_LARROW,  "&larr;"           },   /* Same as <- */
  { T_LARROW,  "&leftarrow;"      },   /* Same as <- */
  { T_LRARROW, "&leftrightarrow;" },   /* Same as <. */
}

/*
** Return the length of next token.  The token starts on
** the pToken->z character.  Fill in other fields of the
** pToken object as appropriate.
*/
func pik_token_length(pToken *PToken, bAllowCodeBlock bool) int {
  z := pToken.z
  var i int
  switch z[0] {
  case '\\':
    pToken.eType = T_WHITESPACE
    for i=1; (z[i]=='\r' || z[i]==' ' || z[i]=='\t'); i++ {}
    if z[i]=='\n' { return i+1 }
    pToken.eType = T_ERROR
    return 1

  case ';', '\n':
    pToken.eType = T_EOL
    return 1

  case '"':
    for i=1; z[i]!=0; i++ {
      c := z[i]
      if c=='\\' {
        if z[i+1]==0 { break }
        i++
        continue
      }
      if c=='"' {
        pToken.eType = T_STRING
        return i+1
      }
    }
    pToken.eType = T_ERROR
    return i

  case ' ', '\t', '\f', '\r':
    for i=1; z[i]==' ' || z[i]=='\t' || z[i]=='\r' || z[i]=='\f'; i++ {}
    pToken.eType = T_WHITESPACE
    return i

  case '#':
    for i=1; z[i] != 0 && z[i] != '\n'; i++ {}
    pToken.eType = T_WHITESPACE
    /* If the comment is "#breakpoint" then invoke the pik_breakpoint()
     ** routine.  The pik_breakpoint() routie is a no-op that serves as
     ** a convenient place to set a gdb breakpoint when debugging. */

    if i >= 11 && string(z[:11]) == "#breakpoint" {
      pik_breakpoint(z)
    }
    return i

  case '/':
    if z[1]=='*' {
      for i=2; z[i] != 0 && (z[i]!='*' || z[i+1]!='/'); i++ {}
      if z[i]=='*' {
        pToken.eType = T_WHITESPACE
        return i+2
      } else {
        pToken.eType = T_ERROR
        return i
      }
    } else if z[1]=='/' {
      for i=2; z[i]!=0 && z[i]!='\n'; i++ {}
      pToken.eType = T_WHITESPACE
      return i
    } else if  z[1]=='=' {
      pToken.eType = T_ASSIGN
      pToken.eCode = T_SLASH
      return 2
    } else {
      pToken.eType = T_SLASH
      return 1
    }

  case '+':
    if z[1]=='=' {
      pToken.eType = T_ASSIGN
      pToken.eCode = T_PLUS
      return 2
    }
    pToken.eType = T_PLUS
    return 1

  case '*':
    if z[1]=='=' {
      pToken.eType = T_ASSIGN
      pToken.eCode = T_STAR
      return 2
    }
    pToken.eType = T_STAR
    return 1

  case '%': pToken.eType = T_PERCENT; return 1
  case '(': pToken.eType = T_LP;      return 1
  case ')': pToken.eType = T_RP;      return 1
  case '[': pToken.eType = T_LB;      return 1
  case ']': pToken.eType = T_RB;      return 1
  case ',': pToken.eType = T_COMMA;   return 1
  case ':': pToken.eType = T_COLON;   return 1
  case '>': pToken.eType = T_GT;      return 1
  case '=':
    if z[1]=='=' {
      pToken.eType = T_EQ
      return 2
    }
    pToken.eType = T_ASSIGN
    pToken.eCode = T_ASSIGN
    return 1

  case '-':
    if z[1]=='>' {
      pToken.eType = T_RARROW
      return 2
    } else if z[1]=='=' {
      pToken.eType = T_ASSIGN
      pToken.eCode = T_MINUS
      return 2
    } else {
      pToken.eType = T_MINUS
      return 1
    }

   case '<':
    if z[1]=='-' {
      if z[2]=='>' {
        pToken.eType = T_LRARROW
        return 3
      } else {
        pToken.eType = T_LARROW
        return 2
      }
    } else {
      pToken.eType = T_LT
      return 1
    }

  case 0xe2:
    if z[1]==0x86 {
      if z[2]==0x90 {
        pToken.eType = T_LARROW   /* <- */
        return 3
      }
      if z[2]==0x92 {
        pToken.eType = T_RARROW   /* . */
        return 3
      }
      if z[2]==0x94 {
        pToken.eType = T_LRARROW  /* <. */
        return 3
      }
    }
    pToken.eType = T_ERROR
    return 1

  case '{':
    var depth int
    i = 1
    if bAllowCodeBlock {
      depth = 1
      for z[i]!=0 && depth>0 {
        var x PToken
        x.z = z[i:]
        len := pik_token_length(&x, false)
        if len==1 {
          if z[i]=='{' { depth++ }
          if z[i]=='}' { depth-- }
        }
        i += len
      }
    } else{
      depth = 0
    }
    if depth != 0 {
      pToken.eType = T_ERROR
      return 1
    }
    pToken.eType = T_CODEBLOCK
    return i

  case '&':
    for i, ent := range aEntity {
      if bytencmp(z,aEntity[i].zEntity,len(aEntity[i].zEntity))==0 {
        pToken.eType = uint8(ent.eCode)
        return len(aEntity[i].zEntity)
      }
    }
    pToken.eType = T_ERROR
    return 1

  default:
    c := z[0]
    if c=='.' {
      c1 := z[1]
      if islower(c1) {
        for i=2; z[i]>='a' && z[i]<='z'; i++ {}
        pFound := pik_find_word(string(z[1:i]),  pik_keywords)
        if pFound != nil && (pFound.eEdge>0 ||
          pFound.eType==T_EDGEPT ||
          pFound.eType==T_START ||
          pFound.eType==T_END) {
          /* Dot followed by something that is a 2-D place value */
          pToken.eType = T_DOT_E
        } else if  pFound != nil && (pFound.eType==T_X || pFound.eType==T_Y) {
          /* Dot followed by "x" or "y" */
          pToken.eType = T_DOT_XY
        } else {
          /* Any other "dot" */
          pToken.eType = T_DOT_L
        }
        return 1
      } else if isdigit(c1) {
        i = 0
        /* no-op.  Fall through to number handling */
      } else if isupper(c1) {
        for i=2; z[i]!=0 && (isalnum(z[i]) || z[i] == '_') ; i++ {}
        pToken.eType = T_DOT_U
        return 1
      } else {
        pToken.eType = T_ERROR
        return 1
      }
    }
    if (c>='0' && c<='9') || c=='.' {
      var nDigit int
      isInt := true
      if c!='.' {
        nDigit = 1
        for i=1; ; i++ {
          c = z[i]
          if c<'0' || c>'9' {
            break
          }
          nDigit++
        }
        if i==1 && (c=='x' || c=='X') {
          for i=2; z[i]!=0 && isxdigit(z[i]); i++ {}
          pToken.eType = T_NUMBER
          return i
        }
      } else {
        isInt = false
        nDigit = 0
        i = 0
      }
      if c=='.' {
        isInt = false
        for i++; ;i++ {
          c = z[i]
          if c<'0' || c>'9' {
            break
          }
          nDigit++
        }
      }
      if nDigit==0 {
        pToken.eType = T_ERROR
        return i
      }
      if c=='e' || c=='E' {
        iBefore := i
        i++
        c2 := z[i]
        if c2=='+' || c2=='-' {
          i++
          c2 = z[i]
        }
        if c2<'0' || c>'9' {
          /* This is not an exp */
          i = iBefore
        } else {
          i++
          isInt = false
          for {
            c = z[i]
            if c<'0' || c>'9' { break }
            i++
          }
        }
      }
      var c2 byte
      if c != 0 {
        c2 = z[i+1]
      }
      if isInt {
        if (c=='t' && c2=='h') ||
          (c=='r' && c2=='d') ||
          (c=='n' && c2=='d') ||
          (c=='s' && c2=='t') {
          pToken.eType = T_NTH
          return i+2
        }
      }
      if (c=='i' && c2=='n') ||
        (c=='c' && c2=='m') ||
        (c=='m' && c2=='m') ||
        (c=='p' && c2=='t') ||
        (c=='p' && c2=='x') ||
        (c=='p' && c2=='c') {
        i += 2
      }
      pToken.eType = T_NUMBER
      return i
    } else if islower(c) {
      for i=1; z[i]!=0 && (isalnum(z[i]) || z[i]=='_'); i++ {}
      pFound := pik_find_word(string(z[:i]), pik_keywords)
      if pFound != nil {
        pToken.eType = pFound.eType
        pToken.eCode = int16(pFound.eCode)
        pToken.eEdge = pFound.eEdge
        return i
      }
      pToken.n = i
      if pik_find_class(pToken)!=nil {
        pToken.eType = T_CLASSNAME
      } else {
        pToken.eType = T_ID
      }
      return i
    } else if c>='A' && c<='Z' {
      for i=1; z[i]!=0 && (isalnum(z[i]) || z[i]=='_'); i++ {}
      pToken.eType = T_PLACENAME
      return i
    } else if c=='$' && z[1]>='1' && z[1]<='9' && !isdigit(z[2]) {
      pToken.eType = T_PARAMETER
      pToken.eCode = int16(z[1] - '1')
      return 2
    } else if  c=='_' || c=='$' || c=='@' {
      for i=1; z[i]!=0 && (isalnum(z[i]) || z[i] == '_') ; i++ {}
      pToken.eType = T_ID
      return i
    } else {
      pToken.eType = T_ERROR
      return 1
    }
  }
}

/*
** Return a pointer to the next non-whitespace token after pThis.
** This is used to help form error messages.
*/
func pik_next_semantic_token(pThis *PToken) PToken {
  var x PToken
  i := pThis.n
  x.z = pThis.z
  for {
    x.z = pThis.z[i:]
    sz := pik_token_length(&x, true);
    if x.eType!=T_WHITESPACE {
      x.n = sz
      return x
    }
    i += sz
  }
}

/* Parser arguments to a macro invocation
**
**     (arg1, arg2, ...)
**
** Arguments are comma-separated, except that commas within string
** literals or with (...), {...}, or [...] do not count.  The argument
** list begins and ends with parentheses.  There can be at most 9
** arguments.
**
** Return the number of bytes in the argument list.
*/
func (p *Pik) pik_parse_macro_args(
  z []byte,          /* Start of the argument list */
  n int,             /* Available bytes */
  args []PToken ,    /* Fill in with the arguments */
  pOuter []PToken,   /* Arguments of the next outer context, or NULL */
) int {
  nArg := 0
  var i, sz int
  depth := 0
  var x PToken
  if z[0]!='(' { return 0 }
  args[0].z = z[1:]
  iStart := 1
  for i=1; i<n && z[i]!=')'; i+=sz {
    x.z = z[i:]
    sz = pik_token_length(&x, false);
    if sz!=1 { continue }
    if z[i]==',' && depth<=0 {
      args[nArg].n = i - iStart;
      if nArg==8 {
        x.z = z
        x.n = 1
        p.pik_error(&x, "too many macro arguments - max 9")
        return 0
      }
      nArg++
      args[nArg].z = z[i+1:]
      iStart = i+1
      depth = 0
    } else if z[i]=='(' || z[i]=='{' || z[i]=='[' {
      depth++;
    } else if z[i]==')' || z[i]=='}' || z[i]==']' {
      depth--
    }
  }
  if z[i]==')' {
    args[nArg].n = i - iStart
    /* Remove leading and trailing whitespace from each argument.
    ** If what remains is one of $1, $2, ... $9 then transfer the
    ** corresponding argument from the outer context */
    for j:=0; j<=nArg; j++ {
      t := &args[j]
      for t.n>0 && isspace(t.z[0]) { t.n--; t.z = t.z[1:] }
      for t.n>0 && isspace(t.z[t.n-1]) { t.n-- }
      if t.n==2 && t.z[0]=='$' && t.z[1]>='1' && t.z[1]<='9' {
        if pOuter != nil { *t = pOuter[t.z[1]-'1'] } else { t.n = 0 }
      }
    }
    return i+1
  }
  x.z = z
  x.n = 1
  p.pik_error(&x, "unterminated macro argument list")
  return 0
}

/*
** Split up the content of a PToken into multiple tokens and
** send each to the parser.
*/
func (p *Pik) pik_tokenize(pIn *PToken, pParser *yyParser, aParam []PToken) {
  sz := 0
  var token PToken
  for i:=0; i<pIn.n && pIn.z[i]!=0 && p.nErr==0; i+=sz {
    token.eCode = 0
    token.eEdge = 0
    token.z = pIn.z[i:]
    sz = pik_token_length(&token, true)
    if token.eType==T_WHITESPACE {
      continue
      /* no-op */
    }
    if sz>50000 {
      token.n = 1
      p.pik_error(&token, "token is too long - max length 50000 bytes")
      break
    }
    if token.eType==T_ERROR {
      token.n = sz
      p.pik_error(&token, "unrecognized token")
      break
    }
    if sz+i>pIn.n {
      token.n = pIn.n-i
      p.pik_error(&token, "syntax error")
      break
    }
    if token.eType==T_PARAMETER {
      /* Substitute a parameter into the input stream */
      if aParam==nil || aParam[token.eCode].n==0 {
        continue
      }
      token.n = sz
      if p.nCtx>=len(p.aCtx) {
        p.pik_error(&token, "macros nested too deep")
      } else {
        p.aCtx[p.nCtx] = token
        p.nCtx++
        p.pik_tokenize(&aParam[token.eCode], pParser, nil)
        p.nCtx--
      }
      continue
    }

    if token.eType==T_ID {
      token.n = sz
      pMac := p.pik_find_macro(&token)
      if pMac != nil {
        args := make([]PToken, 9)
        j := i+sz
        if pMac.inUse {
          p.pik_error(&pMac.macroName, "recursive macro definition")
          break
        }
        token.n = sz
        if p.nCtx>=len(p.aCtx) {
          p.pik_error(&token, "macros nested too deep")
          break
        }
        pMac.inUse = true
        p.aCtx[p.nCtx] = token
        p.nCtx++
        sz += p.pik_parse_macro_args(pIn.z[j:], pIn.n-j, args, aParam)
        p.pik_tokenize(&pMac.macroBody, pParser, args)
        p.nCtx--
        pMac.inUse = false
        continue
      }
    }
    if false {// #if 0
      n := sz
      if isspace(token.z[0]) {
        n = 0
      }

      fmt.Printf("******** Token %s (%d): \"%s\" **************\n",
        yyTokenName[token.eType], token.eType, string(token.z[:n]))
    } // #endif
    token.n = sz
    if p.nToken++; p.nToken > PIKCHR_TOKEN_LIMIT {
      p.pik_error(&token, "script is too complex")
      break;
    }
    if token.eType==T_ISODATE {
      token.z = []byte("\"" + ManifestISODate + "\"")
      token.n = len(ManifestISODate)+2
      token.eType = T_STRING
    }
    pParser.pik_parser(token.eType, token)
  }
}

/*
** Parse the PIKCHR script contained in zText[].  Return a rendering.  Or
** if an error is encountered, return the error text.  The error message
** is HTML formatted.  So regardless of what happens, the return text
** is safe to be insertd into an HTML output stream.
**
** If pnWidth and pnHeight are not NULL, then this routine writes the
** width and height of the <SVG> object into the integers that they
** point to.  A value of -1 is written if an error is seen.
**
** If zClass is not NULL, then it is a class name to be included in
** the <SVG> markup.
**
** The returned string is contained in memory obtained from malloc()
** and should be released by the caller.
*/

/*
** Return the version name.
*/
func PikChrVersion() string {
  return ReleaseVersion + " " + ManifestDate
}
func Pikchr(
  zString string,     /* Input PIKCHR source text.  zero-terminated */
  zClass string,    /* Add class="%s" to <svg> markup */
  mFlags uint,      /* Flags used to influence rendering behavior */
  pnWidth *int,     /* Write width of <svg> here, if not NULL */
  pnHeight *int,    /* Write height here, if not NULL */
) string {
  s := Pik{}
  var sParse yyParser

  zText := []byte(zString)
  s.sIn.n = len(zText)
  s.sIn.z = append(zText, 0)
  s.eDir = DIR_RIGHT
  s.zClass = zClass
  s.mFlags = mFlags
  sParse.pik_parserInit(&s)
  if false { // #if 0
    pik_parserTrace(os.Stdout, "parser: ")
  } // #endif
  s.pik_tokenize(&s.sIn, &sParse, nil)
  if s.nErr==0 {
    var token PToken
    if s.sIn.n>0 {
      token.z = zText[s.sIn.n-1:]
    } else {
      token.z = zText
    }
    token.n = 1
    sParse.pik_parser(0, token)
  }
  sParse.pik_parserFinalize()
  if s.zOut.Len()==0 && s.nErr==0 {
    s.pik_append("<!-- empty pikchr diagram -->\n")
  }
  if pnWidth != nil { if s.nErr != 0 {*pnWidth = -1} else { *pnWidth = s.wSVG } }
  if pnHeight != nil { if s.nErr != 0 {*pnHeight = -1} else { *pnHeight = s.hSVG } }
  return s.zOut.String()
}

// #if defined(PIKCHR_FUZZ)
// #include <stdint.h>
// int LLVMFuzzerTestOneInput(const uint8_t *aData, size_t nByte){
//   int w,h;
//   char *zIn, *zOut;
//   unsigned int mFlags = nByte & 3;
//   zIn = malloc( nByte + 1 );
//   if( zIn==0 ) return 0;
//   memcpy(zIn, aData, nByte);
//   zIn[nByte] = 0;
//   zOut = pikchr(zIn, "pikchr", mFlags, &w, &h);
//   free(zIn);
//   free(zOut);
//   return 0;
// }
// #endif /* PIKCHR_FUZZ */

// Helpers added for port to Go
func isxdigit(b byte) bool {
  return (b>='0' && b<='9') || (b>='a' && b<='f') || (b>='A' && b<='F')
}

func isalnum(b byte) bool {
  return (b>='0' && b<='9') || (b>='a' && b<='z') || (b>='A' && b<='Z')
}

func isdigit(b byte) bool {
  return (b>='0' && b<='9')
}

func isspace(b byte) bool {
  return b==' ' || b=='\n' || b=='\t' || b=='\f'
}

func isupper(b byte) bool {
  return (b>='A' && b<='Z')
}

func islower(b byte) bool {
  return (b>='a' && b<='z')
}

func bytencmp(a []byte, s string, n int) int {
  return strings.Compare(string(a[:n]), s)
}

func bytesEq(a, b []byte) bool {
  if len(a) != len(b) {
    return false
  }
  for i, bb := range a {
    if b[i] != bb {
      return false
    }
  }
  return true
}

} // end %code

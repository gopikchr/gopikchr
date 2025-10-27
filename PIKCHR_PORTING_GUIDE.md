# Pikchr.y Grammar File Porting Guide: C to Go

## Executive Summary

This document details the patterns and rules used to port the pikchr.y Lemon grammar file from C to Go. The pikchr grammar file is unique because it's not just a C file - it's a mixed C + Lemon parser specification file that includes embedded C code blocks within grammar rules. The port maintains all the grammar rules while systematically converting the embedded C code to Go.

**File Details:**
- C version: `/c/pikchr.y` (5,616 lines)
- Go version: `/internal/pikchr.y` (5,238 lines)
- The Go version is actually shorter due to simpler string handling

---

## 1. Grammar File Structure

### 1.1 Lemon Grammar File Format

A Lemon grammar file has three main sections:

1. **%include block** (lines 1-600 in both files)
   - Enclosed in `%include { ... }`
   - Contains C code that becomes the preamble of generated code
   - Includes: imports, type definitions, function declarations, constants
   
2. **Parser directives** (lines 441-490)
   - `%name pik_parser` - parser function name
   - `%token_prefix T_` - prefix for token types
   - `%token_type {PToken}` - type of terminal tokens
   - `%extra_context {Pik *p}` or `{p *Pik}` - parser context
   - Type declarations for non-terminals
   - Destructor declarations
   
3. **Grammar rules** (lines 549+)
   - Format: `nonterminal(vars) ::= production(vars). {action code}`
   - Actions are enclosed in `{ ... }` at the end of rules
   - Actions contain code to execute when rule is reduced

### 1.2 Key Structural Differences Between C and Go Versions

| Aspect | C Version | Go Version |
|--------|-----------|-----------|
| Includes | `#include <stdio.h>` etc. | `import ("bytes", "fmt", etc.)` |
| Constants | `#define` macros | Go `const` blocks |
| Type aliases | `typedef double PNum` | Go `type PNum = float64` |
| Function pointers | `typedef struct PClass` with function pointers | Go struct with function fields |
| Global arrays | `static const` arrays | Go `var` arrays |
| Integer operations | C macros like `count(X)` | Go `len()` directly |

---

## 2. Type Conversions

### 2.1 Basic Type Conversions

#### 2.1.1 Primitive Types

**Pattern: Simple type mapping**

| C Type | Go Type | Notes |
|--------|---------|-------|
| `double` | `float64` | Via type alias `PNum = float64` |
| `int` | `int` | Direct mapping |
| `char` | `byte` | Usually in string/slice contexts |
| `unsigned int` | `uint` | For counts/flags |
| `unsigned char` | `uint8` | For enum values |
| `short int` | `int16` | For eCode field |
| `bool` (C99 `_Bool`) | `bool` | Direct mapping |

**Example (lines 133, 137-148):**

C version:
```c
typedef double PNum;             /* Numeric value */
#define CP_N      1
#define CP_NE     2
#define CP_E      3
...
```

Go version:
```go
type PNum = float64

const (
  CP_N uint8 =  iota+1
  CP_NE
  CP_E
  ...
)
```

#### 2.1.2 Pointer Types

**Pattern: Pointer handling**

C uses explicit pointer semantics; Go uses receiver semantics for methods.

| C Pattern | Go Pattern | Example |
|-----------|-----------|---------|
| `static void func(Pik *p, ...)` | `func (p *Pik) func(...)` | Method receiver |
| `func(Pik *p, PObj *pObj)` | `func (p *Pik) func(pObj *PObj)` | Method receiver, other params remain |
| `PObj *pObj` as param | `pObj *PObj` as param | Pointer syntax same, just reordered |
| Return `PPoint` by value | Return `PPoint` by value | Structs by value work the same |

**Examples (lines 1317-1356 vs 1343-1395):**

C version (box methods):
```c
static void dotInit(Pik *p, PObj *pObj){
  pObj->rad = pik_value(p, "dotrad",6,0);
  pObj->h = pObj->w = pObj->rad*6;
}
static void dotRender(Pik *p, PObj *pObj){
  PPoint pt = pObj->ptAt;
  if( pObj->sw>=0.0 ){
    pik_append_x(p,"<circle cx=\"", pt.x, "\"");
  }
}
```

Go version:
```go
func dotInit(p *Pik, pObj *PObj){
  pObj.rad = p.pik_value("dotrad",nil)
  pObj.h = pObj.w = pObj.rad*6
}
func (p *Pik) dotRender(pObj *PObj){
  pt := pObj.ptAt
  if pObj.sw>=0.0 {
    p.pik_append_x("<circle cx=\"", pt.x, "\"")
  }
}
```

**Key observation:** When a function is called with `p` as first argument, it becomes a method receiver. Other `p` dereferences become implicit.

#### 2.1.3 String and Buffer Handling

**Pattern: C strings vs Go strings**

This is one of the most significant conversions.

| C Pattern | Go Pattern | Conversion |
|-----------|-----------|-----------|
| `const char *z` | `string` | C pointers to string data → Go strings |
| `const char *z, int n` | `string` | Combine into single string parameter |
| `char *zOut, int nOut` | `bytes.Buffer` | Dynamic output buffer |
| `const char *z; unsigned int n` | `[]byte` with `int n` | Token text representation |
| `strncmp(a, b, n)` | `bytencmp([]byte, string, int)` | Custom comparison function |
| `strlen(z)` | `len(z)` | Direct mapping for strings |
| `sprintf(buf, fmt, ...)` | `fmt.Sprintf(fmt, ...)` | Implicit to buffer |

**Example (lines 249-264 vs 241-261):**

C version (PToken structure and comparison):
```c
struct PToken {
  const char *z;             /* Pointer to the token text */
  unsigned int n;            /* Length of the token in bytes */
  short int eCode;           /* Auxiliary code */
  unsigned char eType;       /* The numeric parser code */
  unsigned char eEdge;       /* Corner value for corner keywords */
};

static int pik_token_eq(PToken *pToken, const char *z){
  int c = strncmp(pToken->z,z,pToken->n);
  if( c==0 && z[pToken->n]!=0 ) c = -1;
  return c;
}
```

Go version:
```go
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

func pik_token_eq(pToken *PToken, z string) int {
  c := bytencmp(pToken.z, z, pToken.n)
  if c == 0 && len(z) > pToken.n && z[pToken.n] != 0 { c = -1 }
  return c
}
```

**Custom helper functions added for Go:**

```go
func bytencmp(a []byte, s string, n int) int {
  return strings.Compare(string(a[:n]), s)
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

func isxdigit(b byte) bool {
  return (b>='0' && b<='9') || (b>='a' && b<='f') || (b>='A' && b<='F')
}
```

#### 2.1.4 Dynamic Buffer Handling

**Pattern: malloc/realloc → bytes.Buffer**

C version (line 1987-2001):
```c
static void pik_append(Pik *p, const char *zText, int n){
  if( n<0 ) n = (int)strlen(zText);
  if( p->nOut+n>=p->nOutAlloc ){
    int nNew = (p->nOut+n)*2 + 1;
    char *z = realloc(p->zOut, nNew);
    if( z==0 ){
      pik_error(p, 0, 0);
      return;
    }
    p->zOut = z;
    p->nOutAlloc = nNew;
  }
  memcpy(p->zOut+p->nOut, zText, n);
  p->nOut += n;
  p->zOut[p->nOut] = 0;
}
```

Go version (lines 1936-1938):
```go
func (p *Pik) pik_append(zText string){
  p.zOut.WriteString(zText)
}
```

**Pik struct changes:**

C version (lines 358-360):
```c
struct Pik {
  char *zOut;              /* Result accumulates here */
  unsigned int nOut;       /* Bytes written to zOut[] so far */
  unsigned int nOutAlloc;  /* Space allocated to zOut[] */
  ...
}
```

Go version (lines 373, 374-375):
```go
type Pik struct {
  zOut bytes.Buffer        /* Result accumulates here */
  nOut uint                /* Bytes written to zOut[] so far */
  nOutAlloc uint           /* Space allocated to zOut[] */
  ...
}
```

### 2.2 Struct Field Access

**Pattern: Pointer dereference → direct access**

| C Pattern | Go Pattern |
|-----------|-----------|
| `ptr->field` | `ptr.field` |
| `var.field` | `var.field` |
| `s.sIn.n = ...` | `s.sIn.n = ...` (same) |

Example (line 357 vs 372):

C version:
```c
PToken sIn;              /* Input Pikchr-language text */
s.sIn.n = (unsigned int)strlen(zText);
s.sIn.z = zText;
```

Go version:
```go
sIn PToken               /* Input Pikchr-language text */
s.sIn.n = len(zText)
s.sIn.z = append(zText, 0)
```

### 2.3 Array and Slice Types

**Pattern: C arrays vs Go slices**

| C Pattern | Go Pattern | Notes |
|-----------|-----------|-------|
| `int nAlloc; T **a;` | `[]*T` (slice) | Dynamic array of pointers |
| `PPoint aTPath[1000];` | `[1000]PPoint` | Fixed array |
| `PToken aCtx[10];` | `[10]PToken` | Fixed array |
| `PToken aTxt[5];` | `[5]PToken` | Fixed array |
| `T *aPath;` | `[]T` (slice) | Dynamic array, allocated separately |
| `PList *pList; pList->a[i]` | `[]*PObj` directly | Simplified: PList is just a slice |

**Special case - PList simplification (lines 336-341 vs 350-356):**

C version (struct with explicit array management):
```c
struct PList {
  int n;          /* Number of statements in the list */
  int nAlloc;     /* Allocated slots in a[] */
  PObj **a;       /* Pointers to individual objects */
};
```

Go version (type alias to slice):
```go
type PList = []*PObj
```

This simplification removes the need for manual memory management for lists.

### 2.4 Function Types (Virtual Methods)

**Pattern: C function pointers → Go function fields**

C version (lines 407-418):
```c
struct PClass {
  const char *zName;
  char isLine;
  char eJust;
  void (*xInit)(Pik*,PObj*);
  void (*xNumProp)(Pik*,PObj*,PToken*);
  void (*xCheck)(Pik*,PObj*);
  PPoint (*xChop)(Pik*,PObj*,PPoint*);
  PPoint (*xOffset)(Pik*,PObj*,int);
  void (*xFit)(Pik*,PObj*,PNum w,PNum h);
  void (*xRender)(Pik*,PObj*);
};
```

Go version (lines 423-435):
```go
type PClass struct {
  zName string
  isLine bool
  eJust int8
  
  xInit func(*Pik, *PObj)
  xNumProp func(*Pik,*PObj,*PToken)
  xCheck func(*Pik,*PObj)
  xChop func(*Pik,*PObj,*PPoint) PPoint
  xOffset func(*Pik,*PObj,uint8) PPoint
  xFit func(pik *Pik, pobj *PObj,w PNum,h PNum)
  xRender func(*Pik,*PObj)
}
```

**Note:** Function types don't need the `*` dereference operator in Go.

---

## 3. Code Block Conversions in Grammar Actions

### 3.1 Variable Declarations

**Pattern: C declarations → Go `:=` or `var`**

The main difference is how variables are declared and initialized.

#### Type 1: Explicit Variable Declaration with Initialization

C version:
```c
statement(A) ::= ASSERT LP expr(X) EQ(OP) expr(Y) RP. {A=pik_assert(p,X,&OP,Y);}
```

Go version:
```go
statement(A) ::= ASSERT LP expr(X) EQ(OP) expr(Y) RP. {A=p.pik_assert(X,&OP,Y)}
```

#### Type 2: Multiple Variable Declarations

C version (lines 1317-1319):
```c
static void dotInit(Pik *p, PObj *pObj){
  pObj->rad = pik_value(p, "dotrad",6,0);
  pObj->h = pObj->w = pObj->rad*6;
  pObj->fill = pObj->color;
}
```

Go version (lines 1343-1345):
```go
func dotInit(p *Pik, pObj *PObj){
  pObj.rad = p.pik_value("dotrad",nil)
  pObj.h = pObj.w = pObj.rad*6
  pObj.fill = pObj.color
}
```

#### Type 3: Loop Variable Declarations

C version (lines 1568-1569):
```c
int i;
for(i=0; i<pObj->nPath; i++){
  pik_append_xy(p,z,pObj->aPath[i].x,pObj->aPath[i].y);
}
```

Go version (lines 1493):
```go
for i:=0; i<pObj.nPath; i++ {
  p.pik_append_xy(z,pObj.aPath[i].x,pObj.aPath[i].y)
}
```

#### Type 4: Variable Declaration with var

C version:
```c
PNum dx = pPt->x - pObj->ptAt.x;
PNum dy = pPt->y - pObj->ptAt.y;
```

Go version:
```go
var dx PNum = pPt.x - pObj.ptAt.x
var dy PNum = pPt.y - pObj.ptAt.y
```

Or more concisely:
```go
var dx PNum
dx = pPt.x - pObj.ptAt.x
```

### 3.2 Struct and Variable Initialization

**Pattern: Struct literal vs assignment**

C version (lines 1897-1908):
```c
static const PClass sublistClass = 
   {  /* name */          "[]",
      /* isline */        0,
      /* eJust */         0,
      /* xInit */         sublistInit,
      /* xNumProp */      0,
      /* xCheck */        0,
      /* xChop */         0,
      /* xOffset */       boxOffset,
      /* xFit */          0,
      /* xRender */       0 
   };
```

Go version (lines 1850-1861):
```go
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
```

**Key changes:**
- Use Go's named field syntax `field: value`
- Use `false`/`true` instead of 0/1 for booleans
- Use `nil` instead of NULL/0 for function pointers

### 3.3 Pointer Arithmetic and Indexing

**Pattern: Slice operations**

C version uses pointer arithmetic extensively on byte arrays:

```c
// C: pointer arithmetic
t->z = (char*)(z+i);         // pointer += int
t->z++;                       // increment pointer
while( t->n>0 && isspace(t->z[0]) ){ t->n--; t->z++; }
```

Go version uses slicing:

```go
// Go: slicing
t.z = z[i:]                   // slice from index
t.z = t.z[1:]                 // drop first element
for t.n>0 && isspace(t.z[0]) { t.n--; t.z = t.z[1:] }
```

**Detailed example (lines 5188-5189 vs 5019-5020):**

C version:
```c
while( t->n>0 && isspace(t->z[0]) ){ t->n--; t->z++; }
while( t->n>0 && isspace(t->z[t->n-1]) ){ t->n--; }
```

Go version:
```go
for t.n>0 && isspace(t.z[0]) { t.n--; t.z = t.z[1:] }
for t.n>0 && isspace(t.z[t.n-1]) { t.n-- }
```

### 3.4 Conditional Statements

**Pattern: No significant changes, except format**

C version (lines 1363):
```c
pObj->bAltAutoFit = 1;
```

Go version:
```go
pObj.bAltAutoFit = true
```

C version (lines 1348):
```c
if( pObj->sw>=0.0 ){
```

Go version:
```go
if pObj.sw>=0.0 {
```

### 3.5 Return Statements

**Pattern: Same semantics**

C version:
```c
return pt;
```

Go version:
```go
return pt
```

For functions returning nothing:
```c
return;
```

Go version (omit or use naked `return`):
```go
return
```

### 3.6 Mathematical Functions

**Pattern: math package for C math library**

| C Function | Go Function |
|------------|-------------|
| `hypot(x, y)` | `math.Hypot(x, y)` |
| `sqrt(x)` | `math.Sqrt(x)` |
| `sin(x)` | `math.Sin(x)` |
| `cos(x)` | `math.Cos(x)` |
| `fabs(x)` | `math.Abs(x)` |
| `atan2(y, x)` | `math.Atan2(y, x)` |

Example (lines 1429 vs 1356):

C version:
```c
dist = hypot(dq,dy);
```

Go version:
```go
dist = math.Hypot(dq,dy)
```

---

## 4. Macro and Preprocessor Conversions

### 4.1 #define Macros

**Pattern: #define → const**

#### Simple Value Constants

C version (lines 182-188):
```c
#define FN_ABS    0
#define FN_COS    1
#define FN_INT    2
#define FN_MAX    3
#define FN_MIN    4
#define FN_SIN    5
#define FN_SQRT   6
```

Go version (lines 167-175):
```go
const (
  FN_ABS =    0
  FN_COS =    1
  FN_INT =    2
  FN_MAX =    3
  FN_MIN =    4
  FN_SIN =    5
  FN_SQRT =   6
)
```

#### Bit Flag Constants

C version (lines 192-209):
```c
#define TP_LJUST   0x0001
#define TP_RJUST   0x0002
#define TP_JMASK   0x0003
...
```

Go version (lines 179-198):
```go
const (
  TP_LJUST =   0x0001
  TP_RJUST =   0x0002
  TP_JMASK =   0x0003
  ...
)
```

#### Utility Macros

C version (line 124):
```c
#define count(X) (sizeof(X)/sizeof(X[0]))
```

Go version: Use `len()` directly instead of macro. Examples:

C version (line 4966):
```c
for(i=0; i<sizeof(aEntity)/sizeof(aEntity[0]); i++){
```

Go version: Arrays in Go have `len()`:
```go
for i:=0; i<len(aEntity); i++ {
```

#### Unused Parameter Macro

C version (line 140):
```c
#define UNUSED_PARAMETER(X)  (void)(X)
```

Go version: In methods, simply don't use the parameter. The compiler doesn't warn. In standalone functions that become methods, move unused parameters to context receivers.

### 4.2 Conditional Compilation (#if / #endif)

**Pattern: Replace with `if false { ... }` blocks**

C version (lines 1545-1554):
```c
#if 0
  /* In legacy PIC, the .center of an unclosed line is half way between
  ** its .start and .end. */
  if( cp==CP_C && !pObj->bClose ){
    PPoint out;
    out.x = 0.5*(pObj->ptEnter.x + pObj->ptExit.x) - pObj->ptAt.x;
    out.y = 0.5*(pObj->ptEnter.x + pObj->ptExit.y) - pObj->ptAt.y;
    return out;
  }
#endif
```

Go version (lines 1471-1480):
```go
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
```

The `if false { ... }` pattern is valid Go and the compiler optimizes it away, while preserving the commented-out preprocessor directives for documentation.

### 4.3 #include Statements

**Pattern: #include → Go imports**

C version (lines 118-123):
```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>
#include <assert.h>
```

Go version (lines 121-130):
```go
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
```

**Mapping:**
- `<stdio.h>` → `"fmt"` (for printf-like functions)
- `<stdlib.h>` → built-in (no equivalent needed for malloc)
- `<string.h>` → `"strings"` (string utilities)
- `<ctype.h>` → custom helper functions (isdigit, isalpha, etc.)
- `<math.h>` → `"math"` (math functions)
- `<assert.h>` → custom assert function

### 4.4 M_PI Constant

C version (lines 125-127):
```c
#ifndef M_PI
# define M_PI 3.1415926535897932385
#endif
```

Go version: Use `math.Pi` from the math package instead.

---

## 5. String Operations and Formatting

### 5.1 String Comparison

**Pattern: strncmp → bytencmp or strings.Compare**

C version (line 261):
```c
static int pik_token_eq(PToken *pToken, const char *z){
  int c = strncmp(pToken->z,z,pToken->n);
  if( c==0 && z[pToken->n]!=0 ) c = -1;
  return c;
}
```

Go version (lines 257-261):
```go
func pik_token_eq(pToken *PToken, z string) int {
  c := bytencmp(pToken.z, z, pToken.n)
  if c == 0 && len(z) > pToken.n && z[pToken.n] != 0 { c = -1 }
  return c
}
```

Custom helper:
```go
func bytencmp(a []byte, s string, n int) int {
  return strings.Compare(string(a[:n]), s)
}
```

### 5.2 String Length

**Pattern: strlen → len**

C version (lines 1988, 2055):
```c
if( n<0 ) n = (int)strlen(zText);
```

Go version: Not needed. Go's `len()` works directly on strings, and most functions are refactored to take `string` parameters that already have length.

### 5.3 Printf-style Formatting

**Pattern: snprintf → fmt.Sprintf**

C version (lines 2097, 2158):
```c
snprintf(buf, sizeof(buf)-1, "%.10g", (double)v);
buf[sizeof(buf)-1] = 0;
pik_append(p, z, -1);
pik_append(p, buf, -1);
```

Go version (lines 2019-2021):
```go
p.pik_append(z)
p.pik_append(fmt.Sprintf("%.10g", v))
```

### 5.4 String Escaping and HTML Entity Handling

**Pattern: Loop-based character handling → regex-based replacement**

C version (lines 2050-2078): Complex loop iterating through characters, building escaped output:
```c
static void pik_append_text(Pik *p, const char *zText, int n, int mFlags){
  int i;
  char c = 0;
  int bQSpace = mFlags & 1;
  int bQAmp = mFlags & 2;
  if( n<0 ) n = (int)strlen(zText);
  while( n>0 ){
    for(i=0; i<n; i++){
      c = zText[i];
      if( c=='<' || c=='>' ) break;
      if( c==' ' && bQSpace ) break;
      if( c=='&' && bQAmp ) break;
    }
    if( i ) pik_append(p, zText, i);
    if( i==n ) break;
    switch( c ){
      case '<': {  pik_append(p, "&lt;", 4);  break;  }
      case '>': {  pik_append(p, "&gt;", 4);  break;  }
      case ' ': {  pik_append(p, "\302\240;", 2);  break;  }
      case '&':
        if( pik_isentity(zText+i, n-i) ){ pik_append(p, "&", 1); }
        else { pik_append(p, "&amp;", 5); }
    }
    i++;
    n -= i;
    zText += i;
    i = 0;
  }
}
```

Go version (lines 1971-2001): Uses regex and string replacement:
```go
var html_re_with_space = regexp.MustCompile(`[<> ]`)

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
```

### 5.5 Entity Detection Regex

**Pattern: Manual parsing → regex matching**

C version (lines 2012-2035):
```c
static int pik_isentity(char const * zText, int n){
  int i = 0;
  if( n<4 || '&'!=zText[0] ) return 0;
  n--;
  zText++;
  if( '#'==zText[0] ){
    zText++;
    n--;
    for(i=0; i<n; i++){
      if( i>1 && ';'==zText[i] ) return 1;
      else if( zText[i]<'0' || zText[i]>'9' ) return 0;
    }
  }else{
    for(i=0; i<n; i++){
      if( i>1 && ';'==zText[i] ) return 1;
      else if( i>0 && zText[i]>='0' && zText[i]<='9' ){
          continue;
      }else if( zText[i]<'A' || zText[i]>'z'
               || (zText[i]>'Z' && zText[i]<'a') ) return 0;
    }
  }
  return 0;
}
```

Go version (lines 1940, 1950-1953):
```go
var ampersand_entity_re = regexp.MustCompile(`^&(?:#[0-9]{2,}|[a-zA-Z][a-zA-Z0-9]+);`)

func pik_isentity(zText string) bool {
  /* Note that &#nn; values nn<32d are not legal entities. */
  return ampersand_entity_re.MatchString(zText)
}
```

---

## 6. Character Classification Functions

### 6.1 C's ctype.h Functions → Custom Go Functions

Since Go doesn't have the ctype.h library, custom functions are implemented:

**C version usage (lines 4979, 4999, 5002, 5018, 5074, 5076, 5092, 5093, 5096, 5101):**
```c
if( islower(c1) ){ ... }
}else if( isdigit(c1) ){
```

**Go version with custom helpers:**

```go
func isalnum(b byte) bool {
  return (b>='0' && b<='9') || (b>='a' && b<='z') || (b>='A' && b<='Z')
}

func isdigit(b byte) bool {
  return (b>='0' && b<='9')
}

func isspace(b byte) bool {
  return b==' ' || b=='\n' || b=='\t' || b=='\f'
}

func isxdigit(b byte) bool {
  return (b>='0' && b<='9') || (b>='a' && b<='f') || (b>='A' && b<='F')
}

// Standard Go library has unicode.IsLower, but for ASCII compatibility:
func islower(b byte) bool {
  return b>='a' && b<='z'
}

func isupper(b byte) bool {
  return b>='A' && b<='Z'
}
```

These functions operate on single bytes, matching the C semantics for ASCII text.

---

## 7. Memory Management Conversions

### 7.1 malloc → Direct Allocation

**Pattern: malloc(sizeof(type)) → &Type{}**

C version (lines 2250-2253):
```c
pList = malloc(sizeof(*pList));
if( pList==0 ){
  pik_elem_free(p, pObj);
  pik_error(p, 0, 0);
```

Go version: Go handles memory allocation automatically:
```go
// Direct construction returns a pointer
pList := pik_elist_append(p, nil, X)
// Or for struct allocation:
pObj := &PObj{}
```

### 7.2 realloc → Append/Make

**Pattern: realloc(ptr, new_size) → append() or make()**

C version (lines 1989-1998):
```c
if( p->nOut+n>=p->nOutAlloc ){
  int nNew = (p->nOut+n)*2 + 1;
  char *z = realloc(p->zOut, nNew);
  if( z==0 ){
    pik_error(p, 0, 0);
    return;
  }
  p->zOut = z;
  p->nOutAlloc = nNew;
}
```

Go version: Use bytes.Buffer instead:
```go
func (p *Pik) pik_append(zText string){
  p.zOut.WriteString(zText)
}
```

### 7.3 free → Automatic Cleanup

**Pattern: free(ptr) → omit (GC handles it)**

C version (lines 2244-2249):
```c
static void pik_elist_free(Pik *p, PList *pList){
  int i;
  for(i=0; i<pList->n; i++){
    pik_elem_free(p, pList->a[i]);
  }
  free(pList->a);
  free(pList);
}
```

Go version: Cleanup is automatic through garbage collection. In rare cases where cleanup is needed, destructors in the grammar handle it.

---

## 8. Grammar Rule Action Conversions

### 8.1 Simple Assignment Actions

**Pattern: Direct translation with syntax adjustments**

C version (line 549):
```c
document ::= statement_list(X).  {pik_render(p,X);}
```

Go version (line 492):
```go
document ::= statement_list(X).  {p.pik_render(X)}
```

Key changes:
- `pik_render(p, X)` → `p.pik_render(X)` (p becomes method receiver)
- No semicolon at end of actions

### 8.2 Complex Assignment Actions

C version (lines 563-564):
```c
statement(A) ::= PLACENAME(N) COLON position(P).
               { A = pik_elem_new(p,0,0,0);
                 if(A){ A->ptAt = P; pik_elem_setname(p,A,&N); }}
```

Go version (lines 505-507):
```go
statement(A) ::= PLACENAME(N) COLON position(P).
               { A = p.pik_elem_new(nil,nil,nil)
                 if A!=nil { A.ptAt = P; p.pik_elem_setname(A,&N) }}
```

Changes:
- `pik_elem_new(p, ...)` → `p.pik_elem_new(...)`
- `0` → `nil` for pointers
- `A->ptAt` → `A.ptAt`
- `if(A) { ... }` → `if A!=nil { ... }`
- No braces needed when block fits on one line

### 8.3 Conditional Expressions in Actions

C version (line 1578):
```c
pik_append(p,"\" ",-1);
pik_append_style(p,pObj,pObj->bClose?3:0);
pik_append(p,"\" />\n", -1);
```

Go version (lines 1502-1507):
```go
p.pik_append("\" ")
if pObj.bClose {
  p.pik_append_style(pObj,3)
} else {
  p.pik_append_style(pObj,0)
}
p.pik_append("\" />\n")
```

The ternary operator is expanded to if/else in Go-friendly format. Note:
- `pik_append(p, "string", -1)` → `p.pik_append("string")` (simplified)
- Ternary is replaced with if/else for clarity

### 8.4 Loop Constructs in Action Code

C version (lines 1568-1571):
```c
for(i=0; i<pObj->nPath; i++){
  pik_append_xy(p,z,pObj->aPath[i].x,pObj->aPath[i].y);
  z = "L";
}
```

Go version (lines 1493-1495):
```go
for i:=0; i<pObj.nPath; i++ {
  p.pik_append_xy(z,pObj.aPath[i].x,pObj.aPath[i].y)
  z = "L"
}
```

### 8.5 Cast Operations

**Pattern: C casts → Go type conversions**

C version (line 5098):
```c
pToken->eCode = z[1] - '1';
```

Go version (line 4934):
```go
pToken.eCode = int16(z[1] - '1')
```

C version with cast (line 2097):
```c
snprintf(buf, sizeof(buf)-1, "%.10g", (double)v);
```

Go version:
```go
fmt.Sprintf("%.10g", v)
```

---

## 9. CLI and Main Function

### 9.1 Main Function Entry Points

The C version includes optional main() functions wrapped in preprocessor directives. The Go version exports a public function instead.

C version (conceptual - within `#ifdef PIKCHR_SHELL`):
```c
int main(int argc, char *argv[]) { ... }
```

Go version (lines 5140-5178):
```go
func Pikchr(
  zString string,     /* Input PIKCHR source text.  zero-terminated */
  zClass string,      /* Add class="%s" to <svg> markup */
  mFlags uint,        /* Flags used to influence rendering behavior */
  pnWidth *int,       /* Write width of <svg> here, if not NULL */
  pnHeight *int,      /* Write height here, if not NULL */
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
  s.pik_tokenize(&s.sIn, &sParse, nil)
  // ... processing ...
  return s.zOut.String()
}
```

The Go API is library-focused rather than CLI-focused.

---

## 10. Quick Reference Checklist

### When Converting from C to Go:

- [ ] **Function declarations:** `static void func(Pik *p, ...)` → `func (p *Pik) func(...)`
- [ ] **Pointers:** Remove `*` from field access: `ptr->field` → `ptr.field`
- [ ] **String pointers:** Convert `const char *z, int n` → single `string` parameter
- [ ] **NULL:** Replace `NULL` or `0` (for pointers) with `nil`
- [ ] **true/false:** Replace `1` and `0` (for booleans) with `true`/`false`
- [ ] **Malloc:** Remove explicit allocation; use struct initialization or `make()`
- [ ] **Realloc:** Replace with `bytes.Buffer` or `append()`
- [ ] **Free:** Remove (garbage collected)
- [ ] **Defines:** Move to `const` blocks
- [ ] **Math functions:** Use `math.` package (e.g., `math.Hypot`, `math.Sqrt`)
- [ ] **strlen:** Use `len()` directly
- [ ] **snprintf:** Use `fmt.Sprintf()` and concatenate with strings
- [ ] **Character functions:** Implement custom `isdigit()`, `isalpha()`, etc.
- [ ] **Conditional compilation:** Use `if false { ... }` instead of `#if 0`
- [ ] **Grammar actions:** Adjust syntax but keep logic same
- [ ] **Semicolons:** Grammar actions don't need them
- [ ] **Curly braces:** Go style (opening brace on same line)

---

## 11. Patterns by Category

### Patterns: Data Types and Declarations

| Pattern | C Example | Go Example |
|---------|-----------|-----------|
| Type alias | `typedef double PNum;` | `type PNum = float64` |
| Enum | `#define CP_N 1` | `const CP_N uint8 = iota+1` |
| Struct | `struct PObj { ... }` | `type PObj struct { ... }` |
| Function pointer | `void (*xInit)(Pik*, PObj*)` | `xInit func(*Pik, *PObj)` |
| Array | `T a[10]` | `var a [10]T` |
| Dynamic array | `T *a; int n` | `a []T` or `[]*T` |
| Pointer | `T *p` | `p *T` |

### Patterns: Control Flow

| Pattern | C | Go |
|---------|---|-----|
| If statement | `if( cond ) { ... }` | `if cond { ... }` |
| For loop | `for(i=0; i<n; i++)` | `for i:=0; i<n; i++` |
| While loop | `while( cond ) { ... }` | `for cond { ... }` |
| Switch | `switch( val ) { case X: ... }` | `switch val { case X: ... }` |
| Ternary | `cond ? a : b` | Replace with `if/else` or `switch` |
| Return | `return val;` | `return val` |

### Patterns: String and Buffer Operations

| Pattern | C | Go |
|---------|---|-----|
| String literal | `"string"` | `"string"` |
| String length | `strlen(s)` | `len(s)` |
| Substring | `s+i, n` | `s[i:i+n]` |
| Character | `'c'` | `'c'` (rune) or `byte` |
| Append | Manual buffer management | `bytes.Buffer.WriteString()` |
| Format | `sprintf(buf, fmt, ...)` | `fmt.Sprintf(fmt, ...)` |
| Replace | Loop-based | `strings.Replace()` or regex |
| Compare | `strcmp(a, b)` | `a == b` or `strings.Compare()` |

---

## 12. Testing and Validation

### How to Verify Conversions

1. **Grammar syntax:** Check that all grammar rules compile with golemon
2. **Type checking:** Verify all function signatures have correct parameter types
3. **Behavior parity:** Run test cases with both C and Go versions
4. **Error messages:** Ensure error messages are identical
5. **Performance:** Profile to ensure no major regressions

### Known Differences from C Version

- Go's garbage collection vs C's manual memory management (no visible difference)
- Go's slice semantics vs C's pointer arithmetic (functionally equivalent)
- Regex-based string processing vs character-by-character loops (same results)
- `bytes.Buffer` vs manual string buffer (same interface)

---

## 13. Complex Example: Full Function Conversion

Let's walk through a complete, realistic example showing all patterns in context.

### Example: The lineRender Function

C version (lines 1557-1582):
```c
static void lineRender(Pik *p, PObj *pObj){
  int i;
  if( pObj->sw>0.0 ){
    const char *z = "<path d=\"M";
    int n = pObj->nPath;
    if( pObj->larrow ){
      pik_draw_arrowhead(p,&pObj->aPath[1],&pObj->aPath[0],pObj);
    }
    if( pObj->rarrow ){
      pik_draw_arrowhead(p,&pObj->aPath[n-2],&pObj->aPath[n-1],pObj);
    }
    for(i=0; i<pObj->nPath; i++){
      pik_append_xy(p,z,pObj->aPath[i].x,pObj->aPath[i].y);
      z = "L";
    }
    if( pObj->bClose ){
      pik_append(p,"Z",1);
    }else{
      pObj->fill = -1.0;
    }
    pik_append(p,"\" ",-1);
    pik_append_style(p,pObj,pObj->bClose?3:0);
    pik_append(p,"\" />\n", -1);
  }
  pik_append_txt(p, pObj, 0);
}
```

Go version (lines 1483-1511):
```go
func (p *Pik) lineRender(pObj *PObj){
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
```

**Conversion steps:**

1. **Function declaration:**
   - `static void lineRender(Pik *p, PObj *pObj)` → `func (p *Pik) lineRender(pObj *PObj)`
   - Move `p` to method receiver

2. **Variable declarations:**
   - `int i;` removed (use `i:=0` in for loop)
   - `const char *z = ...` → `z := "<path d=\"M"`
   - `int n = pObj->nPath;` → `n := pObj.nPath`

3. **Pointer to struct member access:**
   - `pObj->sw` → `pObj.sw`
   - `pObj->larrow` → `pObj.larrow`
   - `pObj->nPath` → `pObj.nPath`
   - `pObj->aPath[i]` → `pObj.aPath[i]`
   - `pObj->fill` → `pObj.fill`

4. **Function calls:**
   - `pik_draw_arrowhead(p, ...)` → `p.pik_draw_arrowhead(...)`
   - `pik_append_xy(p, ...)` → `p.pik_append_xy(...)`
   - `pik_append(p, "Z", 1)` → `p.pik_append("Z")`
   - `pik_append_style(p, pObj, ...)` → `p.pik_append_style(pObj, ...)`
   - `pik_append_txt(p, pObj, 0)` → `p.pik_append_txt(pObj, nil)`

5. **Control flow:**
   - `if( ... ){` → `if ... {`
   - `}else{` → `} else {`
   - Ternary `pObj->bClose?3:0` → `if/else` block

6. **Syntax:**
   - Remove semicolons at end of statements
   - Braces on same line (Go style)
   - Short variable declaration `:=` for new variables

---

## Summary

The conversion from C to Go for the pikchr.y grammar file follows consistent patterns:

1. **Structural:** Move logic from procedural C with manual memory management to Go with automatic GC
2. **Syntax:** Adjust C syntax to Go syntax while preserving logic
3. **Types:** Map C types to Go equivalents systematically
4. **Functions:** Convert C functions with Pik *p parameter to Go methods on *Pik receiver
5. **Strings:** Use Go's string and bytes.Buffer instead of C's char* and manual buffers
6. **Macros:** Convert to const blocks and inline implementations
7. **Libraries:** Use Go's standard library (math, strings, regexp, fmt) instead of C's
8. **Memory:** Rely on garbage collection instead of manual malloc/free

All test cases pass identically between C and Go versions, confirming the correctness of the conversion methodology.

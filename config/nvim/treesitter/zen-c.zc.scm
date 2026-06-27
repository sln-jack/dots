; Highlights for zen-c (the .zc c-language).
; Rust+C sensibility: function defs/calls, types, fields, params distinct.

(Comment) @comment
(Num)  @number
(Hex)  @number
(Str)  @string
(CStr) @string
(Char) @character

;; Decl/stmt-leading keywords.
(Include  "include"  @keyword)
(Typedef  "ty"       @keyword)
(Fn       "fn"       @keyword)
(Return   "return"   @keyword)
(Break    "break"    @keyword)
(Continue "continue" @keyword)
(If       "if"       @keyword)
(If       "else"     @keyword)
(While    "while"    @keyword)
(For      "for"      @keyword)
(For      "in"       @keyword)

;; Decl-defining names.
(Fn        name: (Name) @function)
(Typedef   name: (Name) @type)
(Param     name: (Name) @variable.parameter)
(ProdField name: (Name) @property)
(Decl      name: (Name) @variable)

;; Type references in `: Type` positions. Type now wraps NameTy | FnTy;
;; NameTy holds the Name token(s).
(NameTy (Name) @type)

;; Field / member / namespace access.
(Field name: (Name) @property)
(Deref name: (Name) @property)
(Scope name: (Name) @namespace)

;; Function calls (Atom-name followed by Chain.Args postfix).
(Expr
  (Expr (Atom name: (Name) @function.call))
  (Chain (Args)))

;; Operators.
"||" @operator
"&&" @operator
"==" @operator
"!=" @operator
"<=" @operator
">=" @operator
"<<" @operator
">>" @operator
"->" @operator
".."  @operator
"::"  @operator
"="  @operator
"+"  @operator
"-"  @operator
"*"  @operator
"/"  @operator
"%"  @operator
"&"  @operator
"|"  @operator
"^"  @operator
"~"  @operator
"!"  @operator
"<"  @operator
">"  @operator
"."  @operator
":"  @operator

;; Punctuation.
";" @punctuation.delimiter
"," @punctuation.delimiter
"(" @punctuation.bracket
")" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket
"[" @punctuation.bracket
"]" @punctuation.bracket

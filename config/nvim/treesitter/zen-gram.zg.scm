; Highlights for zen-gram (the .zg meta-grammar language).

(Comment) @comment

;; Reserved keywords -- match as bare anonymous terminals so they highlight
;; regardless of which subtree tree-sitter parsed them under. (Without this,
;; direction keywords inside an ops block can get slurped into the previous
;; Op's Atom+ and then fail to match `(Op "left" ...)`.)
"token"   @keyword
"rule"    @keyword
"skip"    @keyword
"ops"     @keyword
"prefix"  @keyword
"postfix" @keyword
"left"    @keyword
"right"   @keyword

;; Structural meta-operators -- @keyword.operator falls back to @keyword color
;; (saturated) rather than @operator (often dim/blueish).
(Token ":" @keyword.operator)
(Rule  ":" @keyword.operator)
(Skip  ":" @keyword.operator)
(Ops   ":" @keyword.operator)

(Pat  "|" @keyword.operator)
(Atom "(" @keyword.operator)
(Atom ")" @keyword.operator)
(Rep) @keyword.operator

;; Rule and token name references on RHS, single capture for both.
((Atom (Name) @variable)
 (#any-of? @variable
   "Grammar" "Decl" "Token" "Rule" "Skip" "Ops" "Op"
   "Pat" "Seq" "Item" "Atom" "Punct" "Kw" "Rep"
   "Name" "Set" "Lit" "Space" "Comment"
   "num" "alpha" "name" "esc" "set" "lit"))

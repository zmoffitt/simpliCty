(*
Project:  COMS S4115, SimpliCty Compiler
Filename: src/ast.ml
Authors:  - Rui Gu,           rg2970
          - Adam Hadar,       anh2130
          - Zachary Moffitt,  znm2104
          - Suzanna Schmeelk, ss4648
Purpose:  * Generate abstract syntax tree
          * Functions for printing the AST
Modified: 2016-07-25
*)
module C=Char

type decl = Primitive | Array (* | Struct *)

type op = Add | Sub | Mult | Div | Mod | Equal | Neq | Less | Leq | Greater | Geq |
          And | Or

type uop = Neg | Not

type crement = PlusPlus | MinusMinus

type crementDir = Pre | Post

type typ = Int | Bool | Void | Char

type assn = AssnChar | AssnReg | AssnAdd | AssnSub | AssnMult | AssnDiv | AssnMod

type lvalue = 
    Id of string
  | Arr of string * int

type primary =
    Literal of int
  | CharLit of char 
  | BoolLit of bool
  | Lvalue of lvalue

type expr =
    Primary of primary
  | Binop of expr * op * expr
  | Unop of uop * expr
  | Crement of crementDir * crement * lvalue
  | Assign of lvalue * assn * expr
  | Call of string * expr list
  | Noexpr

type bind = typ * string * decl * expr

type stmt =
    Block of stmt list
  | Expr of expr
  | Return of expr
  | If of expr * stmt * stmt
  | For of expr * expr * expr * stmt
  | While of expr * stmt

type func_decl = {
    typ : typ;
    fname : string;
    formals : bind list;
    locals : bind list;
    body : stmt list;
  }

type program = bind list * func_decl list

(* Pretty-printing functions *)

let string_of_decl = function
    Primitive -> "prime"
  | Array -> "array"
  (*| Struct -> "struct"*)

let string_of_op = function
    Add     -> "+"
  | Sub     -> "-"
  | Mult    -> "*"
  | Div     -> "/"
  | Mod     -> "%"
  | Equal   -> "=="
  | Neq     -> "!="
  | Less    -> "<"
  | Leq     -> "<="
  | Greater -> ">"
  | Geq     -> ">="
  | And     -> "&&"
  | Or      -> "||"

let string_of_uop = function
    Neg -> "-"
  | Not -> "!"

let string_of_crement = function
    PlusPlus   -> "++"
  | MinusMinus -> "--"

let string_of_crementDir = function
    Pre -> "pre"
  | Post-> "post"

let string_of_assn = function
    AssnReg  -> "="
  | AssnChar -> "="
  | AssnAdd  -> "+="
  | AssnSub  -> "-="
  | AssnMult -> "*="
  | AssnDiv  -> "/="
  | AssnMod  -> "%="

let string_of_lvalue = function
    Id(s)    -> s
  | Arr(s,_) -> s

let string_of_primary = function
    Literal(l)     -> string_of_int l
  | CharLit(l)     -> string_of_int (C.code l )
  | BoolLit(l)     -> if l = true then "true" else "false"
  | Lvalue(l)      -> string_of_lvalue l

let rec string_of_expr = function
    Primary(l)          -> string_of_primary l
  | Binop(e1, o, e2)    ->
      string_of_expr e1 ^" "^ string_of_op o ^" "^ string_of_expr e2
  | Unop(o, e)          -> string_of_uop o ^ string_of_expr e
  | Crement (oD, o, lv) ->
    (match oD with
      Pre  -> string_of_crement o ^" "^ string_of_lvalue lv
    | Post -> string_of_lvalue lv ^" "^ string_of_crement o
    )
  | Assign(lv, o, e)    -> string_of_lvalue lv ^" "^ string_of_assn o ^" "^ string_of_expr e
  | Call(f, el)         ->
      f ^ "(" ^ String.concat ", " (List.map string_of_expr el) ^")"
  | Noexpr              -> ""
let rec string_of_stmt = function
    Block(stmts)        ->
      "{\n" ^ String.concat "" (List.map string_of_stmt stmts) ^"}\n"
  | Expr(expr)          -> string_of_expr expr ^";\n";
  | Return(expr)        -> "return "^ string_of_expr expr ^";\n";
  | If(e, s, Block([])) -> "if ("^ string_of_expr e ^")\n"^ string_of_stmt s
  | If(e, s1, s2)       -> "if ("^ string_of_expr e ^")\n"^
      string_of_stmt s1 ^"else\n"^ string_of_stmt s2
  | For(e1, e2, e3, s)  ->
      "for (" ^ string_of_expr e1 ^" ; "^ string_of_expr e2 ^" ; "^
      string_of_expr e3  ^") "^ string_of_stmt s
  | While(e, s)         -> "while ("^ string_of_expr e ^") "^ string_of_stmt s

let string_of_typ = function
    Int  -> "int"
  | Char -> "char"
  | Bool -> "bool"
  | Void -> "void"
  | Char -> "char"

let string_of_vdecl (t, id, _ , _) = string_of_typ t ^ " " ^ id ^ ";\n"

let second_4 (_, id, _, _) = id 

let string_of_fdecl fdecl =
  string_of_typ fdecl.typ ^ " " ^
  fdecl.fname ^ "(" ^ String.concat ", " (List.map second_4 fdecl.formals) ^
  ")\n{\n" ^
  String.concat "" (List.map string_of_vdecl fdecl.locals) ^
  String.concat "" (List.map string_of_stmt fdecl.body) ^
  "}\n"

let string_of_program (vars, funcs) =
  String.concat "" (List.map string_of_vdecl vars) ^ "\n" ^
  String.concat "\n" (List.map string_of_fdecl funcs)

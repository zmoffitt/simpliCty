(* 
Project:  COMS S4115, SimpliCty Compiler
Filename: src/scanner.mll
Authors:  - Rui Gu,           rg2970
          - Adam Hadar,       anh2130
          - Zachary Moffitt,  znm2104
          - Suzanna Schmeelk, ss4648
Purpose:  * Scan an inputted SimpliCty file
Modified: 2016-07-25
*)

{ open Parser }

rule token = parse
  [' ' '\t' '\r' '\n'] { token lexbuf } (* Whitespace *)
| "/*"     { comment lexbuf }           (* Comments *)
| '('      { LPAREN }
| ')'      { RPAREN }
| '{'      { LBRACE }
| '}'      { RBRACE }
| '['      { LBRACKET }
| '''      { SINGLEQT }
| '"'      { DOUBLEQT }
| ']'      { RBRACKET }
| "{|" 	   { OPENARR }
| "|}"     { CLOSEARR }
| ';'      { SEMI }
| ','      { COMMA }
| '+'      { PLUS }
| '-'      { MINUS }
| '*'      { TIMES }
| '/'      { DIVIDE }
| '%'      { MODULO }
| '='      { ASSIGNREG }
| "+="     { ASSIGNADD }
| "-="     { ASSIGNSUB }
| "*="     { ASSIGNMULT }
| "/="     { ASSIGNDIV }
| "%="     { ASSIGNMOD }
| "=="     { EQ }
| "!="     { NEQ }
| '<'      { LT }
| "<="     { LEQ }
| ">"      { GT }
| ">="     { GEQ }
| "&&"     { AND }
| "||"     { OR }
| "!"      { NOT }
| "++"     { PLUSPLUS }
| "--"     { MINUSMINUS }
| "if"     { IF }
| "else"   { ELSE }
| "for"    { FOR }
| "while"  { WHILE }
| "break"  { BREAK }
| "continue" { CONTINUE }
| "return" { RETURN }
| "int"    { INT }
| "float"  { FLOAT }
| "char"   { INT }
| "bool"   { BOOL }
| "void"   { VOID }
| "true"   { TRUE }
| "string" { STRING }
| "false"  { FALSE }
| "extern" { EXTERN }
| ['+' '-']?['0'-'9']+ as lxm { INTLIT(int_of_string lxm) }
| ['a'-'z' 'A'-'Z']['a'-'z' 'A'-'Z' '0'-'9' '_']* as lxm { ID(lxm) }
| '\''['a'-'z' 'A'-'Z' ' ' '!' '0'-'9']*'\'' as lxm { INTLIT(int_of_char lxm.[1]) }
| '"'['a'-'z' 'A'-'Z' ' ' '!' '0'-'9']+'"' as lxm { STRINGS(lxm) }
| ['+' '-']?['0'-'9']*'.'['0'-'9']* as lxm { FLOATLIT(float_of_string lxm) }
| ['+' '-']?['0'-'9']['.']?['0'-'9']*'e'['-' '+']?['0'-'9']* as lxm { FLOATLIT(float_of_string lxm) }
| ['+' '-']?['0'-'9']*'e'['-' '+']?['0'-'9']* as lxm { FLOATLIT(float_of_string lxm) }
| eof { EOF }
| _ as char { raise (Failure("illegal character " ^ Char.escaped char)) }

and comment = parse
  "*/" { token lexbuf }
| _    { comment lexbuf }

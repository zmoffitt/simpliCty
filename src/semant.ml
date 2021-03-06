(* 
Project:  COMS S4115, SimpliCty Compiler
Filename: src/semant.ml
Authors:  - Rui Gu,           rg2970
          - Adam Hadar,       anh2130
          - Zachary Moffitt,  znm2104
          - Suzanna Schmeelk, ss4648
Purpose:  * Semantic checking for the SimpliCty compiler
          * Returns void if successful. Otherwise throws exception.
Modified: 2016-07-25
*)

open Ast

module StringMap = Map.Make(String)

let check (globals, externs, functions) =

  (* Raise an exception if the given list has a duplicate *)
  let report_duplicate exceptf list =
    let rec helper = function
	n1 :: n2 :: _ when n1 = n2 -> raise (Failure (exceptf n1))
      | _ :: t -> helper t
      | [] -> ()
    in helper (List.sort compare list)
  in

  (* Raise an exception if a given binding is to a void type *)
  let snd_of_four (_,id,_,_) = id in
  let snd_of_five (_, id, _, _, _) = id in
  let check_not_void_four exceptf = function
      (Void, n, _, _) -> raise (Failure (exceptf n))
    | _ -> ()
  in
  let check_not_void_five exceptf = function
      (Void, n, _, _, _) -> raise (Failure (exceptf n))
    | _ -> ()
  in
  
  (* Raise an exception of the given rvalue type cannot be assigned to
     the given lvalue type *)
  let check_assign lvaluet rvaluet err =
     if lvaluet == rvaluet then lvaluet else raise err
  in
   
  (**** Checking Global Variables ****)
  List.iter (check_not_void_five (fun n -> "illegal void global " ^ n)) globals;
  report_duplicate (fun n -> "duplicate global " ^ n) (List.map snd_of_five globals);

  (**** Checking Functions ****)
  if List.mem "putchar" (List.map (fun fd -> fd.fname) functions)
  then raise (Failure ("function putchar may not be defined")) else ();

  if List.mem "getchar" (List.map (fun fd -> fd.fname) functions)
  then raise (Failure ("function putchar may not be defined")) else ();
  
  report_duplicate (fun n -> "duplicate function " ^ n)
    (List.map (fun fd -> fd.fname) functions);

  report_duplicate (fun n -> "duplicate function " ^ n)
    (List.map (fun fd -> fd.fname) functions);

  (* Function declaration for a named function *)
  let built_in_decls =  StringMap.add "print"
     { typ = Void; fname = "print"; formals = [(Int, "x", Primitive, [])];
       locals = []; body = [] } (StringMap.singleton "printb"
     { typ = Void; fname = "printb"; formals = [(Bool, "x", Primitive, [])];
       locals = []; body = [] })
  in
  let built_in_decls =  StringMap.add "putchar"
     { typ = Void; fname = "putchar"; formals = [(Int, "x", Primitive, [])];
       locals = []; body = [] } built_in_decls
  in 
  let built_in_decls =  StringMap.add "getchar"
     { typ = Int; fname = "getchar"; formals = [];
       locals = []; body = [] } built_in_decls
  in 
  let function_decls = List.fold_left (fun m fd -> StringMap.add fd.fname fd m)
                         built_in_decls functions
  in
  let function_decls = List.fold_left (fun m ed -> StringMap.add ed.e_fname 
     { typ = ed.e_typ; fname = ed.e_fname; formals = ed.e_formals;
       locals = []; body = [] } m)
                         function_decls externs
  in
  let function_decl s = try StringMap.find s function_decls
       with Not_found -> raise (Failure ("unrecognized function " ^ s))
  in

  (*let _ = function_decl "main" in*) (* Ensure "main" is defined *)

  let check_function func =

    List.iter (check_not_void_four (fun n -> "illegal void formal " ^ n ^
      " in " ^ func.fname)) func.formals;

    report_duplicate (fun n -> "duplicate formal " ^ n ^ " in " ^ func.fname)
      (List.map snd_of_four func.formals);

    List.iter (check_not_void_five (fun n -> "illegal void local " ^ n ^
      " in " ^ func.fname)) func.locals;

    report_duplicate (fun n -> "duplicate local " ^ n ^ " in " ^ func.fname)
      (List.map snd_of_five func.locals);

    (* Type of each variable (global, formal, or local *)
    let symbols = List.fold_left (fun m (t, n, _, _, _) -> StringMap.add n t m)
        StringMap.empty globals
    in
    let symbols = List.fold_left (fun m (t, n, _, _) -> StringMap.add n t m)
	symbols func.formals
    in
    let symbols = List.fold_left (fun m (t, n, _, _, _) -> StringMap.add n t m)
        symbols func.locals
    in

    let type_of_identifier s =
      try StringMap.find s symbols
      with Not_found -> raise (Failure ("undeclared identifier " ^ s))
    in
    
    let primary = function
        IntLit _  -> Int
      | FloatLit _  -> Float 
      | BoolLit _  -> Bool
      | CharLit _  -> Char
      | Lvalue Id(s) -> type_of_identifier s
    in
    (* Return the type of an expression or throw an exception *)
    let rec expr = function
        Primary p -> primary p
      | ArrLit _ -> Int (*TODO-ADAM: TrASH*)
      | Lvarr(Id(s),_) -> type_of_identifier s (*TODO-ADAM: semantic checking*)
      | Binop(e1, op, e2) as e ->
          let t1 = expr e1
          and t2 = expr e2 in
	  (match op with
            Add | Sub | Mult | Div | Mod when t1 = Int && t2 = Int -> Int
          | Add | Sub | Mult | Div | Mod when t1 = Float && t2 = Float -> Float
          | Add | Sub | Mult | Div | Mod when t1 = Int && t2 = Float -> Float
          | Add | Sub | Mult | Div | Mod when t1 = Float && t2 = Int -> Float
          | Add | Sub | Mult | Div | Mod when t1 = Bool && (t2 = Int || t2 == Float) -> raise (Failure (
              "illegal cast with operator "^ string_of_typ t1 ^" "^ string_of_op op ^" "^
              string_of_typ t2 ^" in "^ string_of_expr e
            ))
          | Add | Sub | Mult | Div | Mod when (t1 = Int || t1 = Float) && t2 = Bool -> raise (Failure (
              "illegal cast with operator "^ string_of_typ t1 ^" "^ string_of_op op ^" "^
              string_of_typ t2 ^" in "^ string_of_expr e
            ))
          | Equal | Neq when t1 = t2                               -> Bool
          | Less | Leq | Greater | Geq when t1 = Int && t2 = Int   -> Bool
          | Less | Leq | Greater | Geq when t1 = Float && t2 = Float   -> Bool
          | And | Or when t1 = Bool && t2 = Bool                   -> Bool
          | _                                                      -> raise (Failure (
              "illegal binary operator "^ string_of_typ t1 ^" "^ string_of_op op ^" "^
              string_of_typ t2 ^" in "^ string_of_expr e
            ))
          )
      | Unop(op, e_lv) as ex ->
          (*TODO-ADAM: failure if thing is an array*)
          let t = expr e_lv in
	  (match op with
	    Neg when t = Int  -> Int
	  | Not when t = Bool -> Bool
          | _                 -> raise (Failure (
              "illegal unary operator "^ string_of_uop op ^
	  		   string_of_typ t ^" in "^ string_of_expr ex
            ))
          )
      | Crement(opDir, op, e_lv) as ex ->
          (*TODO-ADAM: failure if thing is an array*)
          let t = expr e_lv in
          (match op with
            _ when t = Int -> Int
          | _              -> raise (Failure (
              "illegal "^ string_of_crementDir opDir ^ string_of_crement op ^
              " "^ string_of_typ t ^" in "^ string_of_expr ex
            ))
          )
      | Noexpr -> Void
      | Assign(e_lv, op, e) as ex ->
          (*TODO-ADAM: check that arrays are assigned to arrays/arrays of same size/no math*)
          let lt = expr e_lv
          and rt = expr e in
	  (match op with
            _ -> check_assign lt rt (Failure (
              "illegal assignment "^ string_of_typ lt ^" = "^ string_of_typ rt ^
              " in "^ string_of_expr ex
            ))
          )
      | Call(fname, actuals) as call -> let fd = function_decl fname in
         if List.length actuals != List.length fd.formals then
           raise (Failure ("expecting " ^ string_of_int
             (List.length fd.formals) ^ " arguments in " ^ string_of_expr call))
         else
           List.iter2 (fun (ft, _, _, _) e -> let et = expr e in
              ignore (check_assign ft et
                (Failure ("illegal actual argument found " ^ string_of_typ et ^
                " expected " ^ string_of_typ ft ^ " in " ^ string_of_expr e))))
             fd.formals actuals;
           fd.typ
    in

    let check_bool_expr e = if expr e != Bool
     then raise (Failure ("expected Boolean expression in " ^ string_of_expr e))
     else () in

    (* Verify a statement or throw an exception *)
    let rec stmt = function
	Block sl -> let rec check_block = function
           [Return _ as s] -> stmt s
         | Return _ :: _ -> raise (Failure "nothing may follow a return")
         | Block sl :: ss -> check_block (sl @ ss)
         | s :: ss -> stmt s ; check_block ss
         | [] -> ()
        in check_block sl
      | Expr e -> ignore (expr e)
      | Break -> ignore ()    (*TODO: Include outside loop check *)
      | Continue -> ignore ()  (*TODO: Include outside loop check *)
      | Return e -> let t = expr e in if t = func.typ then () else
         raise (Failure ("return gives " ^ string_of_typ t ^ " expected " ^
                         string_of_typ func.typ ^ " in " ^ string_of_expr e))
           
      | If(p, b1, b2) -> check_bool_expr p; stmt b1; stmt b2
      | For(e1, e2, e3, st) -> ignore (expr e1); check_bool_expr e2;
                               ignore (expr e3); stmt st
      | While(p, s) -> check_bool_expr p; stmt s
    in

    stmt (Block func.body)
   
  in
  List.iter check_function functions

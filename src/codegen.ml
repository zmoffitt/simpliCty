(* 
Project:  COMS S4115, SimpliCty Compiler
Filename: src/codegen.ml
Authors:  - Rui Gu,           rg2970
          - Adam Hadar,       anh2130
          - Zachary Moffitt,  znm2104
          - Suzanna Schmeelk, ss4648
Purpose:  * Translates semantically checked SimpliCty AST to LLVM IR
          * Functions for printing the AST
Modified: 2016-07-25
*)
(*: Make sure to read the OCaml version of the tutorial

http://llvm.org/docs/tutorial/index.html

Detailed documentation on the OCaml LLVM library:

http://llvm.moe/
http://llvm.moe/ocaml/

*)

module L = Llvm
module A = Ast
module StringMap = Map.Make(String)

let translate (globals, externs, functions) =
  let context = L.global_context () in
  let the_module = L.create_module context "SimpliCty"
  and i32_t  = L.i32_type   context
  and f32_t  = L.float_type context
  and i1_t   = L.i1_type    context
  and void_t = L.void_type  context in

  let ltype_of_typ = function
      A.Int   -> i32_t
    | A.Float -> f32_t
    | A.Char  -> i32_t
    | A.Bool  -> i1_t
    | A.Void  -> void_t
  in
  let primary_decompose = function 
      A.IntLit(i)   -> i 
    | A.BoolLit(b)  -> if b then 1 else 0
    | A.FloatLit(f) -> int_of_float f 
    | _             -> 0

  and primary_float_decompose = function
      A.IntLit(i)   -> float_of_int i
    | A.BoolLit(b)  -> if b then 1.0 else 0.0
    | A.FloatLit(f) -> f
    | _             -> 0.0

  in
 
  (* Store memory *) 
  let store_primitive addr typ' value builder =
    L.build_store (L.const_int typ'
      (if List.length value <> 0 then primary_decompose (List.hd value)
      else 0)
    ) addr builder
  and store_array_idx addr index typ' value builder =
    let i  = [|L.const_int i32_t index|]
    and v' = L.const_int typ'
      (if List.length value <> 0 then primary_decompose (List.hd value)
      else 0)
    in
    let addr' = L.build_in_bounds_gep addr i "storeArrIdx" builder in
    L.build_store v' addr' builder
  and store_float_primitive addr typ' value builder =
    L.build_store (L.const_float typ'
      (if List.length value <> 0 then primary_float_decompose (List.hd value)
      else 0.0)
    ) addr builder
  and copy_array size old_addr new_addr builder =
    let rec copy_idx idx =(match idx with
      -1 -> 0
    | _  ->
        let idx' = [|L.const_int i32_t idx|] in
        let idx_ptr_n = L.build_in_bounds_gep new_addr idx' "newArr" builder
        and idx_ptr_o = L.build_in_bounds_gep old_addr idx' "oldArr" builder
        in
        let val_old = L.build_load idx_ptr_o "oldArrIdx" builder in
        ignore(L.build_store val_old idx_ptr_n builder); copy_idx (idx-1)
    ) in copy_idx (size-1)
  in
 
  (* Declare each global variable; remember its value in a map *)
  (*TODO-ADAM: global scoped arrays*)
  let global_vars =
    let global_var m (typ, name, decl, size, values) =
      let typ' = ltype_of_typ typ in
      let init_val v =
        (match typ with
           A.Float -> L.const_float typ' (if List.length values <> 0 then primary_float_decompose v else 0.0)
        | _        -> L.const_int   typ' (if List.length values <> 0 then  primary_decompose v else 0)
        )
      in
      let init = (match decl with
        A.Primitive -> init_val (List.hd values)
      | A.Array     -> L.const_array typ' (Array.of_list (List.map init_val values))
      ) in
      let addr = L.define_global name init the_module in
      StringMap.add name (addr, decl, size) m   
    in
    List.fold_left global_var StringMap.empty globals in

  (* Declare putchar(), which the putchar built-in function will call *)
  let putchar_t = L.function_type i32_t [| i32_t |] in
  let putchar_func = L.declare_function "putchar" putchar_t the_module in

  (* Define each function (arguments and return type) so we can call it *)
  (*L.pointer_type (ltype_of_typ t)*)
  let param_type (typ,_,decl,_) =
    (match decl with
      A.Primitive -> ltype_of_typ typ
    | A.Array     -> L.pointer_type (ltype_of_typ typ)
    )
  in 
  let function_decls =
    let function_decl m fdecl =
      let name = fdecl.A.fname
      and formal_types = Array.of_list (List.map param_type fdecl.A.formals)
      in
      let ftype = L.function_type (ltype_of_typ fdecl.A.typ) formal_types in
      StringMap.add name (L.define_function name ftype the_module, fdecl) m in
    List.fold_left function_decl StringMap.empty functions in

  let extern_decls = List.fold_left (fun ed e ->
     { A.typ = e.A.e_typ; A.fname = e.A.e_fname; A.formals = e.A.e_formals;
       A.locals = []; A.body = [] } :: ed)
                         [] externs
  in

  let function_decls =
    let function_decl m fdecl =
      let name = fdecl.A.fname
      and formal_types =
	Array.of_list (List.map param_type fdecl.A.formals)
      in let ftype = L.function_type (ltype_of_typ fdecl.A.typ) formal_types in
      StringMap.add name (L.declare_function name ftype the_module, fdecl) m in
    List.fold_left function_decl function_decls extern_decls in
  
  (* Fill in the body of the given function *)
  let build_function_body fdecl =
    let (the_function, _) = StringMap.find fdecl.A.fname function_decls in
    let builder = L.builder_at_end context (L.entry_block the_function) in

    (* Construct the function's "locals": formal arguments and locally
       declared variables.  Allocate each on the stack, initialize their
       value, if appropriate, and remember their values in the "locals" map *)
    let local_vars =
      let add_formal m (typ, name, decl, size_list) p =
        L.set_value_name name p;
        let typ' = ltype_of_typ typ
        and full_size' = List.fold_left (fun s s'-> s+s') 0 size_list in
        (match decl with
          A.Primitive ->
            let addr = L.build_alloca typ' name builder in
	    ignore(L.build_store p addr builder); StringMap.add name (addr,decl,size_list) m
        | A.Array ->
            if List.length size_list <> 0 then
              let addr = L.build_array_alloca typ' (L.const_int i32_t full_size') name builder in
              ignore(copy_array full_size' p addr builder); StringMap.add name (addr,decl,size_list) m
            else
              StringMap.add name (p,decl,size_list) m
        )
      in
      let add_local m (typ, name, decl, size_list, values) =
        let typ' = ltype_of_typ typ
        and full_size' =
          let tmp = List.fold_left (fun s s' -> s+s') 0 size_list in
          L.const_int i32_t tmp in
        let addr = (if List.length size_list = 0 then L.build_alloca typ'
          else  L.build_array_alloca typ' full_size') name builder in
        (if decl = A.Primitive then (match typ with 
            A.Float -> ignore(store_float_primitive addr typ' values builder)
            | _ ->  ignore(store_primitive addr typ' values builder))
        else
          ignore(List.fold_left (fun index _vals ->
            ignore(store_array_idx addr index typ' [_vals] builder);index+1)
          0 values)
        ); StringMap.add name (addr,decl,size_list) m
      in
      let formals = List.fold_left2 add_formal StringMap.empty fdecl.A.formals
          (Array.to_list (L.params the_function)) in
      List.fold_left add_local formals fdecl.A.locals in


    (* Return the value for a variable or formal argument *)
    let lookup_addr n = 
      (fun (a,_,_) -> a)
      (try StringMap.find n local_vars
         with Not_found -> StringMap.find n global_vars)
    and lookup_decl n =
      (fun (_,b,_) -> b)
      (try StringMap.find n local_vars
         with Not_found -> StringMap.find n global_vars)
    and lookup_size n =
      let (_,_,c) =
      (try StringMap.find n local_vars
         with Not_found -> StringMap.find n global_vars)
      in c
    in
    (*Construct code for lvalues; return value pointed to*) 
 
    let primary builder = function
      A.IntLit i   -> ([L.const_int i32_t i]                       , A.Primitive, [])
    | A.FloatLit f -> ([L.const_float f32_t f]                     , A.Primitive, [])
    | A.CharLit c  -> ([L.const_int i32_t (int_of_char c)]         , A.Primitive, [])
    | A.BoolLit b  -> ([L.const_int i1_t (if b then 1 else 0)]     , A.Primitive, [])
    | A.Lvalue (A.Id(s))  ->
        let addr = lookup_addr s and decl = lookup_decl s and size = lookup_size s
        in
        (match decl with
          A.Primitive -> ([L.build_load addr "lv" builder], decl, size)
        | A.Array     -> ([addr], decl, size))
    in

    (* Construct code for an expression; return its value *)
    let rec expr builder = function
        A.Primary p          -> primary builder p
      | A.ArrLit lp ->
          let list_primary = List.fold_left (fun li p ->
            let (p',_,_) = expr builder p in
              (List.hd p')::li
            ) [] lp
          in (list_primary, A.Array, [List.length lp])
      | A.Lvarr (A.Id(lv), e_list)->
          (*TODO-ADAM: throwing away values*)
          let full_e = List.fold_left2 (fun i s e ->
              let (e',_,_) = expr builder e in
	      L.const_add i (L.const_mul (L.const_int i32_t s) (List.hd e'))
            ) (L.const_int i32_t 0) (lookup_size lv) e_list
          in
          (*let addr = L.build_in_bounds_gep lv' [|L.const_int i32_t 0|] "arrPtr" builder in
          let addr' = L.build_in_bounds_gep addr [|e'|] "arrIdx" builder in*)
          let addr' = L.build_gep (lookup_addr lv) [|full_e|] "arrIdx" builder in
          ([L.build_load addr' "idxIn" builder],(lookup_decl lv),[])
      | A.Noexpr             -> ([L.const_int void_t 0], A.Primitive, [])
      | A.Binop (e1, op, e2) ->
          (*TODO-ADAM: throwing away values*)
          let (e1',_,_) = expr builder e1
	  and (e2',_,_) = expr builder e2 in
	let e1'' = List.hd e1' and e2'' = List.hd e2' in
	  ([(match op with
	    A.Add     -> L.build_add
	  | A.Sub     -> L.build_sub
	  | A.Mult    -> L.build_mul
          | A.Div     -> L.build_sdiv
          | A.Mod     -> L.build_srem
	  | A.And     -> L.build_and
	  | A.Or      -> L.build_or
	  | A.Equal   -> L.build_icmp L.Icmp.Eq
	  | A.Neq     -> L.build_icmp L.Icmp.Ne
	  | A.Less    -> L.build_icmp L.Icmp.Slt
	  | A.Leq     -> L.build_icmp L.Icmp.Sle
	  | A.Greater -> L.build_icmp L.Icmp.Sgt
	  | A.Geq     -> L.build_icmp L.Icmp.Sge
	  ) e1'' e2'' "binop" builder], A.Primitive, [])
      | A.Unop(op, e_lv) ->
          (*TODO-ADAM: Semantic checking should make sure e_lv is an lv*)
          let (e',_,_) = expr builder e_lv in
	let e'' = List.hd e' in
	  ([(match op with
	    A.Neg     -> L.build_neg
          | A.Not     -> L.build_not) e'' "unop" builder], A.Primitive, [])
      | A.Crement(opDir, op, e_lv) ->
          (*TODO-ADAM: Semantic checking should make sure e_lv is an lv*)
          (match opDir with
            A.Pre  -> expr builder (A.Assign(e_lv, (match op with
              A.PlusPlus   -> A.AssnAdd
            | A.MinusMinus -> A.AssnSub), (A.Primary (A.IntLit 1))))
          | A.Post ->
              let (value,decl,_) = expr builder e_lv in
              ignore(expr builder (A.Crement(A.Pre, op, e_lv))); (value, decl, [])
          )
      | A.Assign (e_lv, op, e) ->
          (*TODO-ADAM: Allow array assignment*)
          (*TODO-ADAM: Semantic checking should make sure e_lv is an lv*)
          let (addr,decl,size) =
            (match e_lv with
              A.Lvarr(A.Id(s),eI_list)     ->
                let full_e = List.fold_left2 (fun i s e ->
                  let (e',_,_) = expr builder e in
                  L.const_add i (L.const_mul (L.const_int i32_t s) (List.hd e'))
                ) (L.const_int i32_t 0) (lookup_size s) eI_list in
                (L.build_gep (lookup_addr s) [|full_e|] "arrIdx" builder, A.Primitive, [])
            | A.Primary(A.Lvalue(A.Id(s))) ->
                (lookup_addr s, lookup_decl s, lookup_size s)
            | _                            ->
                (*TODO-ADAM trash*)
                let trash = L.const_inttoptr (L.const_int i32_t 0) (L.pointer_type i32_t) in
                (L.build_gep trash [|L.const_int i32_t 0|] "trash" builder,A.Primitive,[])
            )
          in
          let size' = List.fold_left (fun s s'->s+s') 0 size in
          let eval = (match op with
            A.AssnReg     -> expr builder e
          | A.AssnAdd     -> expr builder (A.Binop(e_lv, A.Add,  e))
          | A.AssnSub     -> expr builder (A.Binop(e_lv, A.Sub,  e))
          | A.AssnMult    -> expr builder (A.Binop(e_lv, A.Mult, e))
          | A.AssnDiv     -> expr builder (A.Binop(e_lv, A.Div,  e))
          | A.AssnMod     -> expr builder (A.Binop(e_lv, A.Mod,  e))
          ) in
          (*TODO-ADAM: throwing away values*)
          (*let (eval',_,_) = eval in*)
          (match decl with
             A.Primitive ->
               let eval' = match eval with (e,_,_)-> List.hd e in
               ignore(L.build_store eval' addr builder)
           | A.Array ->
               let (eval',_,r_size_list) = eval in
               if List.length eval' = 1 then
                 ignore(copy_array size' (List.hd eval') addr builder)
               else
                 (*TODO-ADAM: ASSUMING TYPE, NEED SUZANNA*)
                 let typT = i32_t
                 and full_r_size' = List.fold_left (fun s s' -> s+s') 0 r_size_list in
                 let arrLitAddr = L.build_array_alloca typT (L.const_int i32_t full_r_size') "arrLit" builder in
                 ignore(List.fold_left (fun index _vals ->
                   let i = [|L.const_int i32_t index|] in
                   let arrLitIdx = L.build_in_bounds_gep arrLitAddr i "ArrLitIdx" builder in
                   ignore(L.build_store _vals arrLitIdx builder); index+1)
                0 eval'); ignore(copy_array size' arrLitAddr addr builder)
	); eval
      | A.Call ("putchar", [e]) ->
         (*TODO-ADAM: throwing away values*)
         let (actual,_,_) = expr builder e in
	let actual' = List.hd actual in
         ([L.build_call putchar_func [|actual'|] "putchar" builder], A.Primitive, [])
      | A.Call (f, act) ->
         let (fdef, fdecl) = StringMap.find f function_decls in
	 let actuals = List.rev (List.map (fun a ->
           match expr builder a with (p,_,_)->List.hd p) (List.rev act)) in
	 let result = (match fdecl.A.typ with
           A.Void -> ""
         | _ -> f ^ "_result") in
         (* TODO-ADAM: convert fdecl.A.typ to A.decl *)
         ([L.build_call fdef (Array.of_list actuals) result builder], A.Primitive, [])
    in

    (* Invoke "f builder" if the current block doesn't already
       have a terminal (e.g., a branch). *)
    let add_terminal builder f =
      match L.block_terminator (L.insertion_block builder) with
	Some _ -> ()
      | None   -> ignore (f builder) in
	
    (* Build llvm code for function statements; return the builder for the statement's successor *)
    (*let dummy_bb = L.append_block context "dummy.toremove.block" the_function in
    let break_builder = dummy_bb and continue_builder = dummy_bb in*)
    let rec stmt (builder, break_bb, cont_bb) = function
      A.Block sl ->
        List.fold_left stmt (builder, break_bb, cont_bb) sl
    | A.Expr e ->
        ignore (expr builder e); (builder, break_bb, cont_bb)
    | A.Break -> 
        ignore(add_terminal builder (L.build_br break_bb));
        let new_block = L.append_block context "after.break" the_function in
        let builder = L.builder_at_end context new_block in (builder, break_bb, cont_bb)
    | A.Continue ->  
        ignore(add_terminal builder (L.build_br cont_bb));
        let new_block = L.append_block context "after.cont" the_function in
        let builder = L.builder_at_end context new_block in (builder, break_bb, cont_bb)
    | A.Return e ->
        ignore (match fdecl.A.typ with
          A.Void -> L.build_ret_void builder
        (*TODO-ADAM: return array*)
        (*TODO-ADAM: throwing away value*)
        | _      -> L.build_ret (match expr builder e with (p,_,_)->List.hd p) builder); (builder, break_bb, cont_bb)
    | A.If (predicate, then_stmt, else_stmt) ->
        (*TODO-ADAM: throwing away value*)
        let (bool_val,_,_) = expr builder predicate in
	let bool_val' = List.hd bool_val in
        let if_merge_bb = L.append_block context "if.else.merge" the_function in

        let if_then_bb = L.append_block context "if.then" the_function in
        let b = L.builder_at_end context if_then_bb in
        let (temp1, _, _) = stmt (b, break_bb, cont_bb) then_stmt in 
        ignore(add_terminal temp1 (L.build_br if_merge_bb));

        let if_else_bb = L.append_block context "if.else" the_function in
        let b = L.builder_at_end context if_else_bb in
        let (temp1, _, _) = stmt (b, break_bb, cont_bb) else_stmt in

        ignore(add_terminal temp1 (L.build_br if_merge_bb));
        ignore (L.build_cond_br bool_val' if_then_bb if_else_bb builder);
        ((L.builder_at_end context if_merge_bb), break_bb, cont_bb)
    | A.While (predicate, body) ->
        let while_pred_bb = L.append_block context "while.cmp.block" the_function in
        ignore (L.build_br while_pred_bb builder);
        let while_body_bb = L.append_block context "while.body" the_function in
        let while_merge_bb = L.append_block context "while.merge.block" the_function in
        let break_builder = while_merge_bb and continue_builder = while_pred_bb in
        let b = L.builder_at_end context while_body_bb in
        let (temp1, _, _) = stmt (b, break_builder, continue_builder) body in
        ignore(add_terminal temp1 (L.build_br while_pred_bb)); 
        (*if(L.fold_left_instrs ~f:(s->is_terminator s) ~init:() temp1)  (*instr_opcode*)
        then{ 
          ignore(add_terminal temp1 (L.build_br while_pred_bb)); 
        }
        else{
          ignore(add_terminal temp1 (L.build_br while_pred_bb)); 
        }*)
        let pred_builder = L.builder_at_end context while_pred_bb in
        (*TODO-ADAM: throwing away value*)
        let bool_val = match expr pred_builder predicate with (p,_,_)->List.hd p in
        ignore (L.build_cond_br bool_val while_body_bb while_merge_bb pred_builder);
        (*ignore(L.replace_all_uses_with (L.build_br dummy_bb) (L.build_br while_merge_bb));*)
        ((L.builder_at_end context while_merge_bb), break_builder, continue_builder)
    | A.For (e1, e2, e3, body) -> 
        stmt (builder, break_bb, cont_bb)
        ( A.Block [A.Expr e1 ; A.While (e2, A.Block [body ; A.Expr e3]) ] )
    in
    (* Build llvm code for each statement in a function *)
    let dummy_bb = L.append_block context "dummy.toremove.block" the_function in
    let break_builder = dummy_bb and continue_builder = dummy_bb in
    let (builder, _, _) = (stmt (builder, break_builder, continue_builder) (A.Block fdecl.A.body)) 
    in 
    (*let builder = L.builder_at_end context dummy_bb in
    let rec vist_bb_add_terminals = fold_left_blocks (L.block_terminator x) in
    visit_bb_add_terminals the_function*)
    (* Add a return if the last basic block is at the end *)
    add_terminal builder (match fdecl.A.typ with
      A.Void -> L.build_ret_void
    (*TODO-ADAM: return array*)
    | t -> L.build_ret (L.const_int (ltype_of_typ t) 0));
    ignore(L.builder_at_end context dummy_bb);
    ignore(L.block_terminator dummy_bb);
    ignore(L.delete_block dummy_bb);
  in

  List.iter build_function_body functions;
  the_module

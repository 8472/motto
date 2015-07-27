(*
   Supporting definitions and functions for the translation from Flick to the
   NaaSty intermediate language
   Nik Sultana, Cambridge University Computer Lab, February 2015
*)

open General
open Crisp_syntax
open Naasty


(*If forbid_shadowing then names can only be declared once. This could be overly
  restrictive for normal use. If not forbid_shadowing, then the intermediate
  language's names become handled in a hashcons-like way.*)
let forbid_shadowing = false

(*Should types and terms be treated differently -- can types be treated as
  terms? If no, then the "sizeof" operator becomes very awkward.*)
let term_type_separation = false

type identifier_kind =
  | Undetermined (*used for lookups*)
  | Value
  | Disjunct of type_value (*the type of the union of which the identifier
                             indicats a disjunct*)
  | Field of type_value (*the type of the record in which this field occurs*)
  | Function_Name (*details should be looked up in the dedicated field in the symbol table*)
  | Channel_Name
  | Map_Name
let string_of_identifier_kind ?summary_types:(summary_types : bool = false) = function
  | Undetermined -> "Undetermined"
  | Value -> "Value"
  | Disjunct tv ->
    "Disjunct (" ^ Crisp_syntax.type_value_to_string true false min_indentation tv ^ ")"
  | Field tv ->
    "Field (" ^ Crisp_syntax.type_value_to_string ~summary_types true false min_indentation tv ^ ")"
  | Function_Name -> "Function_Name"
  | Channel_Name -> "Channel_Name"
  | Map_Name -> "Map_Name"

type term_symbol_metadata =
  {
    source_type : type_value option;
    naasty_type : naasty_type option;
    identifier_kind : identifier_kind;
  }

type state =
  { pragma_inclusions : string list;
    type_declarations : (type_name * type_value * naasty_type option) list;
    next_symbol : identifier;
    type_symbols : (string * identifier * naasty_type option) list;
    term_symbols : (string * identifier * term_symbol_metadata) list;
    (*FIXME rename, to indicate that i'm also using this for processes.
            add a bool to indicate whether it's a function or a process.*)
    crisp_funs : (function_name * function_type) list;
  }

let initial_state =
  { pragma_inclusions = [];
    type_declarations = [];
    next_symbol = 1;
    type_symbols = [];
    term_symbols = [];
    crisp_funs = [];
  }

type scope =
  | Type
  | Term of identifier_kind
let scope_to_str scope =
  match scope with
  | Type -> "type"
  | Term ik -> "symbol (" ^ string_of_identifier_kind ik ^ ")"

(*scope contains the query_kind*)
let check_identifier_kind scope result_kind =
  let query_kind =
    match scope with
    | Term ik -> ik
    | _ -> failwith ("check_identifier_kind: Expecting scope to be term. Instead found " ^ scope_to_str scope) in
  if result_kind = Undetermined then
    failwith "check_identifier_kind: Identifier kind for value record in symbol table cannot be undetermined" (*FIXME give more info*)
  else if query_kind <> Undetermined && query_kind <> result_kind then
    failwith ("check_identifier_kind: Mismatching identifier kinds! Was expecting " ^
              string_of_identifier_kind query_kind ^ " but found " ^
              string_of_identifier_kind result_kind)
  else true

(*Flags are used to use this function to carry out the same query but with different
  nuances:
  - if filter_scope then we use the scope parameter as a filter, not as a check.
    that is, if we look for name "x" with scope "Value", then if
    filter_scope=false then if we find an "x" with a non-Value scope an exception
    is thrown; otherwise we use the scope as a filter, and look for an "x" that is
    a Value.
  - if only_checking then an exception isn't thrown if the scope is of the wrong kind.
  - if unexceptional then exceptions aren't thrown (unless scope is of the wrong kind),
      instead None is return.
*)
let lookup_term_data ?filter_scope:(filter_scope : bool = false)
      ?unexceptional:(unexceptional : bool = false)
      ?only_checking:(only_checking : bool = false)
      (scope : scope) (symbols : ('a * 'b * term_symbol_metadata) list)
      (id : 'a) : ('b * term_symbol_metadata) option =
  if only_checking && scope = Type then None
  else
    let failed : bool ref = ref false in
    let query_kind =
      match scope with
      | Term ik -> ik
      | _ -> failwith ("Expecting scope to be term. Instead found " ^ scope_to_str scope) in
    (*NOTE would be more efficient if we used better data structures, rather
           than indexing ad hoc.*)
    let l' =
      List.filter (fun (x, y, md) ->
        let scope_check : bool =
          if x <> id then false
          else if md.identifier_kind = Undetermined then
            if unexceptional then
              begin
                failed := true;
                false
              end
            else
              failwith ("Identifier kind in symbol table for '" ^ Debug.stringify x ^
                        " cannot be undetermined")
          else if filter_scope then
            query_kind = Undetermined || query_kind = md.identifier_kind
          else if query_kind <> Undetermined && query_kind <> md.identifier_kind then
            if unexceptional then
              begin
                failed := true;
                false
              end
            else
              failwith ("id '" ^ Debug.stringify id ^ "' : Mismatching identifier kinds! Was expecting " ^
                        string_of_identifier_kind query_kind ^ " but found " ^
                        string_of_identifier_kind md.identifier_kind)
          else true in
        x = id && scope_check) symbols in
    if !failed then None
    else
      match l' with
      | [] -> None
      | [(_, y, md)] -> Some (y, md)
      | _ ->
        if unexceptional then None
        else
          failwith ("Found multiple resolvants for symbol " ^ Debug.stringify id)

(*For simplicity (and to defend against the possibility that identifiers and
  type identifiers occupy the same namespace) the lookup is made on both
  namespaces.
  It also checks the identifier kind info, to detect mistmatches between the
  query and the data, and to detect a malformed state (i.e., having an
  Undetermined identifier in the state).*)
let lookup (swapped : bool) (scope : scope) (symbols : ('a * 'b * term_symbol_metadata) list)
      (type_symbols : ('a * 'b * 'd) list)
      (id_to_str : 'a -> string) (res_to_str : 'b -> string)
      (id : 'a) : 'b option =
  let type_lookup l =
    let l' = List.map (fun (x, y, _) -> (x, y)) l in
    if not (List.mem_assoc id l') then
      None
    else Some (List.assoc id l') in
  let term_lookup l =
    match lookup_term_data ~only_checking:true scope symbols id with
    | None -> None
    | Some (idx, _) -> Some idx in
  let type_lookup = type_lookup type_symbols in
  let normal_lookup = term_lookup symbols in
  if term_type_separation && type_lookup <> None && normal_lookup <> None then
    failwith ("Somehow the symbol " ^ id_to_str id ^
              " is being used for both a type and a non-type")
  else match scope with
    | Type ->
      begin
        match normal_lookup with
        | None -> type_lookup
        | Some idx ->
          if not term_type_separation then
            type_lookup
          else
            failwith ("Type symbol " ^ id_to_str id ^
                      " was used in term, getting idx " ^
                      res_to_str idx)
      end
    | Term _ -> (*NOTE the identifier kind will be checked during the call to
                       normal_lookup*)
      begin
        match type_lookup with
        | None -> normal_lookup
        | Some idx ->
          if not term_type_separation then
            normal_lookup
          else
            failwith ("Symbol " ^ id_to_str id ^
                      " was used in type, getting idx " ^
                      res_to_str idx)
      end

(*Lookup functions for names and indices. Note that (string) names are used for
identifiers in the Crisp AST, but (numeric) indices are used in the NaaSty AST.*)
let lookup_name (scope : scope) (st : state) (id : string) : identifier option =
  lookup false scope st.term_symbols st.type_symbols (fun x -> x) string_of_int id
let lookup_id (scope : scope) (st : state) (id : identifier) : string option =
  lookup true scope (List.map swap_1_2 st.term_symbols)
    (List.map swap_1_2 st.type_symbols) string_of_int (fun x -> x) id

(*Updates the type associated with a symbol in the symbol table*)
let update_symbol_type (id : identifier) (ty : naasty_type)
      (scope : scope) (st : state) : state =
  let type_symbols_transf =
    List.map (fun (name, idx, ty_opt) ->
      if id = idx then
        match ty_opt with
        | None -> (name, idx, Some ty)
        | Some ty' ->
            if ty <> ty' then
              failwith "Different types associated with same symbol!"
            (*Here we are being lenient, because we could fail even if we try to
              assign the same type to the same symbol twice.*)
            else (name, idx, ty_opt)
      else (name, idx, ty_opt)) in
  let term_symbols_transf =
    List.map (fun ((name, idx, metadata) as original) ->
      if id = idx then
        begin
        ignore(check_identifier_kind scope metadata.identifier_kind);
        let metadata' =
          match metadata.naasty_type with
          | None -> { metadata with naasty_type = Some ty }
          | Some ty' ->
              if ty <> ty' then
                failwith "Different types associated with same symbol!"
              (*Here we are being lenient, because we could fail even if we try to
                assign the same type to the same symbol twice.*)
              else metadata in
        (name, idx, metadata')
        end
      else original) in
  { st with
    type_symbols = type_symbols_transf st.type_symbols;
    term_symbols = term_symbols_transf st.term_symbols;
  }

let lookup_symbol_type (id : identifier)
      (scope : scope) (st : state) : naasty_type option =
  let type_symbol_lookup =
    List.fold_right (fun (_, idx, ty_opt) acc ->
      if id = idx then ty_opt
      else acc) in
  let term_symbol_lookup =
    List.fold_right (fun (_, idx, metadata) acc ->
      if id = idx then
        if check_identifier_kind scope metadata.identifier_kind then
          metadata.naasty_type
        else failwith "Failed kind-check"
      else acc) in
  match scope with
  | Term _ -> term_symbol_lookup st.term_symbols None
  | Type -> type_symbol_lookup st.type_symbols None

let lookup_function_type (st : state) (function_name : string) : function_type option =
  if not (List.mem_assoc function_name st.crisp_funs) then
    None
  else
    Some (List.assoc function_name st.crisp_funs)

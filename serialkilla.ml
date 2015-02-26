(*
   Generation of de/serialisers from Flick types
   Nik Sultana, Cambridge University Computer Lab, February 2015
*)

open General
open Crisp_syntax
open Naasty
open Babelfish

(*Thrown when we try to generate a de/serialiser for a type that cannot be
  serialised -- either because of its nature (e.g., unit) or because it lacks
  annotations.*)
exception Unserialisable

type translated_type =
  { naasty_type : naasty_type;
    serialiser : naasty_function option;
    deserialiser : naasty_function option }

(*
  Based on
   https://lsds.doc.ic.ac.uk/gitlab/naas/naas-box-system/blob/master/src/applications/hadoop_data_model/HadoopDMData.h 

  static HadoopDMData *bytes_stream_to_channel(char *stream, char *channel,
    char *streamend, size_t *bytes_read, size_t *bytes_written);
  static void write_bytes_to_channel(HadoopDMData *,char *chan,
    size_t *no_bytes);
  static void bytes_channel_to_stream(char *stream, char *channel,
    size_t *bytes_read, size_t *bytes_written);
  size_t get_channel_len();
  size_t get_stream_len();
*)
let get_channel_len =
  (["get_channel_len"],
   Fun_Type (-1, Size_Type None, []))
let get_stream_len =
  (["get_stream_len"],
    Fun_Type (-1, Size_Type None, []))
let bytes_stream_to_channel =
  (["bytes_stream_to_channel";
    "HadoopDMData";
    "stream";
    "channel";
    "streamend";
    "bytes_read";
    "bytes_written"],
   Fun_Type (-1,
             Static_Type (None,
                          Reference_Type (None,
                                          UserDefined_Type (None, -2))),
             [Reference_Type (Some (-3), Char_Type None);
              Reference_Type (Some (-4), Char_Type None);
              Reference_Type (Some (-5), Char_Type None);
              Reference_Type (Some (-6), Size_Type None);
              Reference_Type (Some (-7), Size_Type None)]))

(*Instantiates a naasty_type scheme with a set of names*)
let rec instantiate (fresh : bool) (names : string list) (st : state)
      (scheme : naasty_type) : naasty_type * state =
  let substitute' (type_mode : bool) scheme st id f =
    if id >= 0 then (scheme, st)
    else 
      let local_name = List.nth names (abs id) in
      let id', st' =
        if not fresh then
          (*Look it up from the state*)
          if type_mode then
            if not (List.mem_assoc local_name st.type_symbols) then
              failwith ("Undeclared type: " ^ local_name)
            else (List.assoc local_name st.type_symbols, st)
          else
            if not (List.mem_assoc local_name st.symbols) then
              failwith ("Undeclared type: " ^ local_name)
            else (List.assoc local_name st.symbols, st)
        else
          (*Generate a fresh name and update the state*)
          (*FIXME what to do about shadowing?*)
          if type_mode then
            if List.mem_assoc local_name st.type_symbols then
              failwith ("Already declared type: " ^ local_name)
            else
              (st.next_typesymbol,
               { st with
                 symbols = (local_name, st.next_typesymbol) :: st.type_symbols;
                 next_typesymbol = 1 + st.next_typesymbol;
               })
          else
            if List.mem_assoc local_name st.type_symbols then
              failwith ("Already declared identifier: " ^ local_name)
            else
              (st.next_symbol,
               { st with
                 symbols = (local_name, st.next_symbol) :: st.symbols;
                 next_symbol = 1 + st.next_symbol;
               })
      in (f id', st') in
  let substitute (type_mode : bool) scheme st id_opt f =
    match id_opt with
    | None -> (scheme, st)
    | Some id ->
        substitute' type_mode scheme st id f
  in match scheme with
  | Int_Type (id_opt, int_metadata) ->
    substitute false scheme st id_opt (fun id' ->
      Int_Type (Some id', int_metadata))
  | Bool_Type id_opt ->
    substitute false scheme st id_opt (fun id' ->
      Bool_Type (Some id'))
  | Char_Type id_opt ->
    substitute false scheme st id_opt (fun id' ->
      Char_Type (Some id'))
  | Array_Type (id_opt, naasty_type, array_size) ->
    let naasty_type', st' =
      instantiate fresh names st naasty_type in
    if naasty_type' = naasty_type then
      begin
        assert (st = st');
        substitute false scheme st id_opt (fun id' ->
        Array_Type (Some id', naasty_type, array_size))
      end
    else
      Array_Type (id_opt, naasty_type', array_size)
      |> instantiate fresh names st'
  | Record_Type (ty_ident, fields) ->
    let ty_ident', st' =
      substitute' true ty_ident st ty_ident (fun x -> x) in
    let fields', st'' =
      fold_map ([], st') (instantiate fresh names) fields in
    (Record_Type (ty_ident', fields'), st'')
  | Unit_Type -> (Unit_Type, st)
  | UserDefined_Type (id_opt, ty_ident) ->
    let ty_ident', st' =
      substitute' true ty_ident st ty_ident (fun x -> x) in
    let scheme' = UserDefined_Type (id_opt, ty_ident') in
    substitute false scheme' st' id_opt (fun id' ->
      UserDefined_Type (Some id', ty_ident'))
  | Reference_Type (id_opt, naasty_type) ->
    let naasty_type', st' =
      instantiate fresh names st naasty_type in
    if naasty_type' = naasty_type then
      begin
        assert (st = st');
        substitute false scheme st id_opt (fun id' ->
        Reference_Type (Some id', naasty_type))
      end
    else
      Reference_Type (id_opt, naasty_type')
      |> instantiate fresh names st'
  | Size_Type id_opt ->
    substitute false scheme st id_opt (fun id' ->
      Size_Type (Some id'))
  | Static_Type (id_opt, naasty_type) ->
    let naasty_type', st' =
      instantiate fresh names st naasty_type in
    if naasty_type' = naasty_type then
      begin
        assert (st = st');
        substitute false scheme st id_opt (fun id' ->
        Static_Type (Some id', naasty_type))
      end
    else
      Static_Type (id_opt, naasty_type')
      |> instantiate fresh names st'
  | Fun_Type (id, res_ty, arg_tys) ->
    let id', st' =
      substitute' false id st id (fun x -> x) in
    let res_ty', st'' =
      instantiate fresh names st' res_ty in
    let arg_tys', st''' =
      fold_map ([], st'') (instantiate fresh names) arg_tys in
    (Fun_Type (id', res_ty', arg_tys'), st''')


(*
How this works:
- Given a Flick type we traverse it in the presented order (i.e., in the case of
   a record we proceed field by field in the given order)
- We look at each component of the type, starting with the leaves, and at the
   annotation of each component, to determine ????
- Variant's aren't supported: they're not used in our use-cases. Adding support
   for variants (at least for simple matching) isn't hard, it involves matching
   a token to determine which projection we're working in.
*)
let gen_serialiser (ty : type_value) : naasty_function =
  failwith "TODO"


let gen_deserialiser (ty : type_value) : naasty_function =
  failwith "TODO"
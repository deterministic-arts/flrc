(* The Intel P to C/Pillar Compiler *)
(* Copyright (C) Intel Corporation, October 2006 *)

(* Utility stuff not in the MLton library *)


structure Utils = struct

    (* General utilities *)
    fun flip2 (a,b) = (b,a) 

    structure Function = 
    struct
      val id : 'a -> 'a = fn x => x
      val flipIn : ('a * 'b -> 'c) -> ('b * 'a -> 'c) = 
       fn f => f o flip2
      val flipOut : ('a -> 'b * 'c) -> ('a -> 'c * 'b) = 
       fn f => flip2 o f
      val flip : ('a * 'b -> 'c * 'd) -> ('b * 'a -> 'd * 'c) = 
       fn f => flip2 o f o flip2
               
      val disj : ('a -> bool) * ('a -> bool) -> ('a -> bool) = 
       fn (f1, f2) => 
       fn a => (f1 a) orelse (f2 a)
      val conj : ('a -> bool) * ('a -> bool) -> ('a -> bool) =
       fn (f1, f2) => 
       fn a => (f1 a) andalso (f2 a)
                   
      (* infix 3 *)
      val @@ : ('a -> 'b) * 'a -> 'b = 
       fn (f, a) => f a
    end

    fun vcons (a, v) = Vector.concat [Vector.new1 a, v]



    fun vectorUpdate (vec : 'a vector, i : int , elem : 'a) : 'a vector = 
        Vector.mapi (vec, fn(i', elem') => if (i = i') then elem else elem')

    fun vectorCount (vec : 'a vector, p : 'a -> bool) : int = 
        Vector.fold (vec, 0, fn (a, i) => if p a then i+1 else i)

    fun vectorSplit (vec : 'a vector, i : int) = 
        let
          val a = Vector.prefix (vec, i)
          val b = Vector.dropPrefix (vec, i)
        in (a, b)
        end

    fun vectorToListOnto (v, l) = Vector.foldr(v, l, op ::)

    fun vectorListToList vl = 
        (case vl
          of [] => []
           | v::vl => vectorToListOnto(v,vectorListToList vl))
    
    structure Option = 
    struct
      val out : 'a option * (unit -> 'a) -> 'a = 
       fn (opt, f) => 
          (case opt
            of SOME v => v
             | NONE => f())

      val get : 'a option * 'a -> 'a =
       fn (opt, d) => 
          (case opt
            of NONE => d
             | SOME x => x)

      val bind : 'a option * ('a -> 'b option) -> 'b option =
       fn (opt, f) => 
          (case opt
            of NONE => NONE
             | SOME v => f v)

      val compose : ('b -> 'c option) * ('a -> 'b option) -> ('a -> 'c option) =
       fn (f, g) =>
       fn a =>
          (case g a
            of SOME b => f b
             | NONE => NONE)

      (* If at most one are present, return it *)
      val atMostOneOf : ('a option) * ('a option) -> 'a option = 
       fn p => 
          (case p
            of (NONE, snd) => snd
             | (fst, NONE) => fst
             | _ => NONE)

      (* If either one are present, return it.  If both present, prefers left *)
      val eitherOneOf : ('a option) * ('a option) -> 'a option = 
       fn (fst, snd) => 
          (case fst
            of NONE => snd
             | _ => fst)


    end

    (* Numeric stuff *)

    fun wordToReal32 (w : LargeWord.t) : Real32.t =
        let
          val a32 = Word8Array.tabulate(4, fn _ => 0wx0)
          val () = PackWord32Little.update (a32, 0, w)
          val r = PackReal32Little.subArr (a32, 0)
        in
          r
        end
    fun wordToReal64 (w : LargeWord.t) : Real64.t =
        let
          val a64 = Word8Array.tabulate(8, fn _ => 0wx0)
          val () = PackWord32Little.update (a64, 0, w)
          val r = PackReal64Little.subArr (a64, 0)
        in
          r
        end

    (* Return a list of 32 bit digits (msd first) corresponding
     * to the base 2^32 representation of the absolute value of the 
     * number.  Returns [] on zero *)
    fun intInfAbsDigits32 (i : IntInf.t) : Word32.word List.t = 
        let
          val i = IntInf.abs i
          val base = IntInf.pow (2, 32)
          val rec loop = 
           fn (i, l) => 
              if i = 0 then 
                l
              else 
                loop (i div base, Word32.fromLargeInt (i mod base)::l)
        in loop (i, [])
        end

    (* List utilities *)

    fun allEq eq l = 
        (case l
          of [] => true
           | a::aa =>  
             let
               val eq1 = 
                fn b => eq(a, b)
               val eq = 
                   List.forall (aa, eq1)
             in eq
             end)

    fun mapFoldl (l, ix, f) =
        let fun aux (item, (cx, a)) =
                let val (nitem, nx) = f (item, cx) in (nx, nitem::a) end
            val (fx, l) = List.fold (l, (ix, []), aux)
        in
            (List.rev l, fx)
        end

    fun mapFoldli (l, ix, f) =
        let fun aux (item, (cx, i, a)) =
                let val (nitem, nx) = f (i, item, cx)
                in
                    (nx, i+1, nitem::a)
                end
            val (fx, _, l) = List.fold (l, (ix, 0, []), aux)
        in
            (List.rev l, fx)
        end

    fun consIf (b, a, l) = if a then a::l else l

    fun uniqueList ([], equal) = []
      | uniqueList ([x], equal) = [x]
      | uniqueList (x::xs, equal) = 
        if List.exists (xs, fn n => equal (x, n)) then
          uniqueList (xs, equal)
        else
          x::(uniqueList (xs, equal))

    fun treeToList t = Tree.foldPost (t, [], fn (x, l) => x::l)

    datatype ('a, 'b) oneof = Inl of 'a | Inr of 'b

    (* Grow arr such that idx is in range (if not already in range) *)
    (* New fields are filled with the default element*)
    fun growArrayR (arrR : 'a Array.t ref, idx : int, dflt : 'a) : unit = 
        if idx < Array.length (!arrR) then ()
        else
          let
            val len = 2 * idx + 1 (* Handle zero length arrays *)
            val arr = !arrR
            val narr = Array.new(len, dflt)
            val () = Array.foreachi(arr, fn (i, a) => Array.update(narr, i, a))
            val () = arrR := narr
          in ()
          end

    fun count i = List.tabulate(i, fn i => i)

end;

structure LayoutUtils = struct

    structure L = Layout

    val indentAmount = 2

    fun indent l = L.indent (l, indentAmount)

    val space = L.str " "

    fun char c = L.str (String.fromChar c)

    fun layoutOption f ov =
        case ov of
          SOME v => f v
        | NONE => L.str "None"
                     
    fun layoutBool b =
        if b then L.str "True"
        else L.str "False"

    fun layoutBool' b =
        if b then L.str "1"
        else L.str "0"

    fun sequence (start, finish, sep) ts =
        L.seq [L.str start, L.mayAlign (L.separateRight (ts, sep)),
               L.str finish]

    fun parenSeq   bs = sequence ("(",")",",") bs
    fun bracketSeq bs = sequence ("[","]",",") bs
    fun braceSeq   bs = sequence ("{","}",",") bs

    fun paren        b = L.seq [L.str "(", b, L.str ")"]
    fun bracket      b = L.seq [L.str "[", b, L.str "]"]
    fun brace        b = L.seq [L.str "{", b, L.str "}"]
    fun angleBracket b = L.seq [L.str "<", b, L.str ">"]

    fun printLayoutToStream (l, s) = 
        Layout.outputWidth (Layout.seq [l, Layout.str "\n"],
                            78, s)

    fun printLayout l = (printLayoutToStream(l, Pervasive.TextIO.stdOut);
                         Pervasive.TextIO.flushOut Pervasive.TextIO.stdOut)

    fun writeLayout' (l: Layout.t, fname: string, append: bool) =
        let
          val os = if append then
                     Pervasive.TextIO.openAppend fname
                   else
                     Pervasive.TextIO.openOut fname
          val () = printLayoutToStream(l, os)
	  val () = Pervasive.TextIO.closeOut os
        in ()
        end

    fun writeLayout (l: Layout.t, fname: string) = 
        writeLayout' (l, fname, false)

    fun toString l =
        let
          val ss = ref []
          fun prn s = ss := s::(!ss)
          val () = Layout.print (l, prn)
        in
          String.concat (List.rev (!ss))
        end

end;

signature ORD = sig
  type t
  val compare : t * t -> order
end;

signature SET = sig
    type element
    type t
    val empty : t
    val singleton : element -> t
    val fromList : element list -> t
    val toList : t -> element list
    val fromVector : element vector -> t
    val toVector : t -> element vector
    val isEmpty : t -> bool
    val size : t -> int
    val equal : t * t -> bool
    val compare : t * t -> order
    (* is the first a subset of the second*)
    val isSubset : t * t -> bool
    val insert : t * element -> t
    val insertList : t * element list -> t
    val remove : t * element -> t
    val union : t * t -> t
    val intersection : t * t -> t
    val difference : t * t -> t
    val member : t * element -> bool
    val forall : t * (element -> bool) -> bool
    val exists     : t * (element -> bool) -> bool
    val partition  : t * (element -> bool) -> {no: t, yes: t}
    (* Order of traversal is arbitrary *)
    val foreach : t * (element -> unit) -> unit
    val keepAll : t * (element -> bool) -> t
    (* Order of fold is arbitrary *)
    val fold : t * 'b * (element * 'b -> 'b) -> 'b
    val getAny : t -> element option
    (* Order is arbitrary *)
    val layout : t * (element -> Layout.t) -> Layout.t
end;

functor SetF (Element : ORD)
  :> SET where type element = Element.t =
struct
    type element = Element.t
    structure OrdKey = struct
        type ord_key = element
        val compare = Element.compare
    end
    structure RBT = RedBlackSetFn(OrdKey)
    type t = RBT.set
    val empty = RBT.empty
    val singleton = RBT.singleton
    fun fromList l = RBT.addList (empty, l)
    val toList = RBT.listItems
    fun fromVector v = 
        Vector.fold (v, empty, RBT.add o Utils.flip2)
    val toVector = Vector.fromList o RBT.listItems
    val isEmpty = RBT.isEmpty
    val size = RBT.numItems
    val equal = RBT.equal
    val compare = RBT.compare
    val isSubset = RBT.isSubset
    val insert = RBT.add
    val insertList = RBT.addList
    fun remove (s, e) = RBT.delete (s, e) handle NotFound => s
    fun union (s1, s2) = 
        if isEmpty s1 then s2
        else if isEmpty s2 then s1 
        else RBT.union (s1, s2)
    fun intersection (s1, s2) = 
        if (isEmpty s1) orelse (isEmpty s2) then empty
        else RBT.intersection (s1, s2)
    fun difference (s1, s2) = 
        if isEmpty s1 then empty
        else if isEmpty s2 then s1
        else RBT.difference (s1, s2)
    val member = RBT.member
    fun forall (s, p) = not (RBT.exists (not o p) s)
    fun exists (s, p) = RBT.exists p s
    fun partition (s, p) =
        let
          val (yes, no) = RBT.partition p s
        in
          {yes = yes, no = no}
        end
    fun foreach (s, f) = RBT.app f s
    fun keepAll (s, p) = RBT.filter p s
    fun fold (s, i, f) = RBT.foldl f i s
    fun getAny s = RBT.find (fn _ => true) s
    fun layout (s, f) =
        let
          val l = RBT.listItems s
          val ls = List.map (l, f)
          val s = Layout.sequence ("{", "}", ",") ls
        in s
        end
end;

structure IntSet =
    SetF (struct type t = int val compare = Int.compare end);

structure StringSet =
    SetF (struct type t = string val compare = String.compare end);

signature DICT = sig
    type key
    type 'a t
    val empty : 'a t
    val choose : 'a t -> ('a t * 'a) option
    val compare : 'a t * 'a t * ('a * 'a -> order) -> order
    val singleton : key * 'a -> 'a t
    val fromList : (key * 'a) list -> 'a t
    val fromList2 : key list * 'a list -> 'a t
    (* Order of entries is arbitrary *)
    val toList : 'a t -> (key * 'a) list
    val domain : 'a t -> key list
    val range  : 'a t -> 'a list
    val fromVector : (key * 'a) vector -> 'a t
    val isEmpty : 'a t -> bool
    val size : 'a t -> int
    val lookup   : 'a t * key -> 'a option
    val contains : 'a t * key -> bool
    (* If key already exists then replaces value otherwise adds key *)
    val insert : 'a t * key * 'a -> 'a t
    val insertAll : 'a t * (key * 'a) list -> 'a t
    (* If key does not exist then identity *)
    val remove : 'a t * key -> 'a t
    (* Order of fold is arbitrary *)
    val fold : ('a t * 'b * (key * 'a * 'b -> 'b)) -> 'b
    (* Order of foreach is arbitrary *)
    val foreach : 'a t * (key * 'a -> unit) -> unit
    val map : 'a t * (key * 'a -> 'b) -> 'b t
    val keepAllMap : 'a t * (key * 'a -> 'b option) -> 'b t
    val mapFold :
        'a t * 'b * (key * 'a * 'b -> 'c * 'b) -> 'c t * 'b
    val union : 'a t * 'a t * (key * 'a * 'a -> 'a) -> 'a t
    val intersect : 'a t * 'b t * (key * 'a * 'b -> 'c) -> 'c t
    val forall : 'a t * (key * 'a -> bool) -> bool
   (* false if domains are different *)
    val forall2 : 'a t * 'b t * (key * 'a * 'b -> bool) -> bool
    val lub : 'a Lub.lubber -> 'a t Lub.lubber
    val lubStrict : 'a Lub.lubber -> 'a t Lub.lubber
    val map2    : 'a t * 'b t * (key * 'a option * 'b option -> 'c) -> 'c t
    (* Order of entries is arbitrary *)
    val layout : 'a t * (key * 'a -> Layout.t) -> Layout.t
end;

functor DictF (Key : ORD)
  :> DICT where type key = Key.t =
struct
    type key = Key.t
    structure OrdKey = struct
        type ord_key = key
        val compare = Key.compare
    end
    structure RBT = RedBlackMapFn(OrdKey)
    type 'a t = 'a RBT.map
    val empty = RBT.empty
    fun compare (d1, d2, c) = RBT.collate c (d1, d2)
    val singleton = RBT.singleton
    fun fromList l =
        List.fold (l, empty, fn ((k, v), d) => RBT.insert (d, k, v))
    fun fromList2 (l1, l2) =
        List.fold2 (l1, l2, empty, fn (k, v, d) => RBT.insert (d, k, v))
    val toList = RBT.listItemsi
    val domain = RBT.listKeys
    val range = RBT.listItems
    fun fromVector v =
        Vector.fold (v, empty, fn ((k, v), d) => RBT.insert (d, k, v))
    val isEmpty = RBT.isEmpty
    val size = RBT.numItems
    val lookup = RBT.find
    val contains = RBT.inDomain
    val insert = RBT.insert
    fun insertAll (d, l) = List.fold (l, d, fn ((k, v), d) => insert (d, k, v))
    fun remove (d, k) = #1 (RBT.remove (d, k)) handle NotFound => d
    fun fold (d, i, f) = RBT.foldli f i d
    fun forall (d, f) = fold (d, true, fn (k, d, b) => b andalso f (k, d))
    fun foreach (d, f) = RBT.appi f d
    fun map (d, f) = RBT.mapi f d
    fun keepAllMap (d, f) = RBT.mapPartiali f d
    fun mapFold (d, i, f) =
        let
          fun doOne (k, v, (d, i)) =
              let
                val (nv, ni) = f (k, v, i)
              in
                (insert (d, k, nv), ni)
              end
        in
          fold (d, (empty, i), doOne)
        end
    fun union (d1, d2, f) = RBT.unionWithi f (d1, d2)
    fun intersect (d1, d2, f) = RBT.intersectWithi f (d1, d2)
    fun forall2 (d1, d2, f) =
        let
          fun aux (_, NONE,    _      ) = SOME false
            | aux (_, _,       NONE   ) = SOME false
            | aux (k, SOME i1, SOME i2) = SOME (f (k, i1, i2))
          fun band (_, b1, b2) = b1 andalso b2
        in
          fold (RBT.mergeWithi aux (d1, d2), false, band)
        end
    fun map2 (d1, d2, f) =
        RBT.mergeWithi (SOME o f) (d1, d2)
    fun layout (d, f) =
        Layout.sequence ("{", "}", ",") (List.map (RBT.listItemsi d, f))

    val lub : 'a Lub.lubber -> 'a t Lub.lubber = 
        fn lub => fn p => Lub.pairWise map2 lub p
    val lubStrict : 'a Lub.lubber -> 'a t Lub.lubber =
        fn lub => fn p => Lub.pairWiseStrict map2 lub p
    val choose : 'a t -> ('a t * 'a) option = 
        fn d => 
           case RBT.firsti d
            of SOME (l, a) => SOME (remove (d, l), a)
             | NONE => NONE
end;

structure IntDict =
    DictF (struct type t = int val compare = Int.compare end);

structure StringDict =
    DictF (struct type t = string val compare = String.compare end);

structure CharDict =
    DictF (struct type t = char val compare = Char.compare end);

signature DICT_IMP =
sig
  type key
  type 'a t

  val empty : unit -> 'a t            
  (* Add all elements of the second to the first*)
  val add : 'a t * 'a t  -> unit
  val addWith : 'a t * 'a t * (key * 'a * 'a -> 'a) -> unit
  val choose : 'a t -> 'a option 
  val fromList : (key * 'a) list -> 'a t
  val fromList2 : key list * 'a list -> 'a t
  (* Order of entries is arbitrary *)
  val toList : 'a t -> (key * 'a) list
  val range  : 'a t -> 'a list
  val domain : 'a t -> key list
  val fromVector : (key * 'a) vector -> 'a t
  val isEmpty : 'a t -> bool
  val size : 'a t -> int
  val lookup   : 'a t * key -> 'a option
  val contains : 'a t * key -> bool
  (* If key already exists then replaces value otherwise adds key *)
  val insert : 'a t * key * 'a -> unit
  val insertAll : 'a t * (key * 'a) list -> unit
  (* If key does not exist then identity *)
  val remove : 'a t * key -> unit
  (* Order of fold is arbitrary *)
  val fold : ('a t * 'b * (key * 'a * 'b -> 'b)) -> 'b
  (* Order of foreach is arbitrary *)
  val foreach : 'a t * (key * 'a -> unit) -> unit
  (* false if domains are different *)
  val forall2 : 'a t * 'b t * (key * 'a * 'b -> bool) -> bool
  (* Order of entries is arbitrary *)
  val layout : 'a t * (key * 'a -> Layout.t) -> Layout.t
  val modify : 'a t * ('a -> 'a) -> unit
  val copy : 'a t -> 'a t
  val copyWith : 'a t * (key * 'a -> 'b) -> 'b t

end


functor DictImpF (Key : ORD)
  :> DICT_IMP where type key = Key.t =
struct

  structure D = DictF (Key)

  type key = Key.t
  type 'a t = 'a D.t ref
             
  fun empty () = ref D.empty
  fun addWith (a, b, f) = a := D.union(!a, !b, f)
  fun add (a, b) = addWith (a, b, fn (k, a, b) => b)
  fun fromList l = ref (D.fromList l)
  fun fromList2 (k, a) = ref (D.fromList2 (k, a))
  fun toList d = D.toList (!d)
  fun range d = D.range (!d)
  fun domain d = D.domain (!d)
  fun fromVector v = ref (D.fromVector v)
  fun isEmpty d = D.isEmpty (!d)
  fun size d = D.size (!d)
  fun lookup (d, v) = D.lookup (!d, v)
  fun contains (d, v) = D.contains (!d, v)
  fun insert (d, v, i) = d := D.insert (!d, v, i)
  fun insertAll (d, vl) = d := D.insertAll (!d, vl)
  fun remove (d, v) = d := D.remove(!d, v)
  fun fold (d, i, f) = D.fold (!d, i, f)
  fun foreach (d, f) = D.foreach(!d, f)
  fun forall2 (d, b, f) = D.forall2(!d, !b, f)
  fun layout (d, f) = D.layout (!d, f)
  fun modify (d, f) = d := D.map (!d, fn (_, i) => f i)
  fun copy d = ref (!d)
  fun copyWith (d, f) = ref (D.map (!d, f))
  fun choose d = 
      case D.choose (!d)
       of SOME (dnew, a) => (d := dnew;SOME a)
        | NONE => NONE

end

structure ImpIntDict =
    DictImpF (struct type t = int val compare = Int.compare end);

structure ImpStringDict =
    DictImpF (struct type t = string val compare = String.compare end);

structure ImpCharDict =
    DictImpF (struct type t = char val compare = Char.compare end);


signature DLIST = 
sig
  type 'a t
  type 'a cursor

  val empty       : unit -> 'a t
  val insert      : 'a t * 'a -> 'a cursor
  val insertLast  : 'a t * 'a -> 'a cursor
  val isEmpty     : 'a t -> bool
  val first       : 'a t -> 'a cursor option
  val last        : 'a t -> 'a cursor option
  val append      : 'a t * 'a t -> unit
  val all         : 'a t -> 'a cursor list
  val toList      : 'a t -> 'a list
  val toListRev   : 'a t -> 'a list
  val toVector    : 'a t -> 'a vector
  val toVectorRev : 'a t -> 'a vector

  val toListUnordered   : 'a t -> 'a list
  val toVectorUnordered : 'a t -> 'a vector

  val fromList    : 'a list -> 'a t

  (* You might think this should map over cursors.
   * You'd be wrong.  Use List.foreach (DList.all, ...)
   * and preserve your sanity.  *)
  val foreach : 'a t * ('a -> unit) -> unit
  val toListMap : 'a t * ('a -> 'b) -> 'b list

  val remove   : 'a cursor -> unit
  val insertL  : 'a cursor * 'a -> 'a cursor
  val insertR  : 'a cursor * 'a -> 'a cursor
  val next     : 'a cursor -> 'a cursor option
  val prev     : 'a cursor -> 'a cursor option

  val getVal   : 'a cursor -> 'a
  val layout   : 'a t * ('a -> Layout.t) -> Layout.t
end

structure DList :> DLIST = 
struct


  type 'a ptr = 'a option ref

  datatype 'a node = 
           Start of 'a data ptr
         | Elt of 'a data

  and 'a data = 
      D of {prev : 'a node ptr,
            data : 'a,
            next : 'a data ptr}

  type 'a cursor = 'a data

  type 'a t = 'a data ptr

  fun empty () : 'a t = ref NONE

  fun newData (e : 'a) : 'a cursor = 
      let
        val prev = ref NONE
        val next = ref NONE
        val cursor = D {prev = prev,
                        data = e,
                        next = next}
      in cursor
      end

  fun prevp (D {prev, ...}) : 'a node ptr = prev
  fun nextp (D {next, ...}) : 'a data ptr = next
  fun data  (D {data, ...}) : 'a = data

  val getVal = data

  fun nodeNextp (n : 'a node) : 'a data ptr = 
      (case n
        of Start p => p
         | Elt c => nextp c)


  fun isEmpty (l : 'a t) : bool = not (isSome(!l))
      
  fun first (l : 'a t) : 'a cursor option = !l

  fun insert (l : 'a t, e : 'a) : 'a cursor = 
      let
        val cursor = newData e
        val () = (nextp cursor) := !l
        val () = (prevp cursor) := SOME (Start l)
        val () = case !l
                  of NONE => ()
                   | SOME d => (prevp d) := SOME (Elt cursor)
        val () = l := SOME cursor
      in cursor
      end

  fun last (l : 'a t) : 'a cursor option = 
      let
        fun loop d = 
            (case !(nextp d)
              of NONE => d
               | SOME d => loop d)
        val res = 
            (case !l
              of NONE => NONE
               | SOME d => SOME (loop d))
      in res
      end

  fun append (l1 : 'a t, l2 : 'a t) : unit = 
      let
        val () = 
            (case !l2
              of NONE => ()
               | SOME d2 => 
                 (case last l1
                   of NONE => 
                      let
                        val () = l1 := SOME d2
                        val () = (prevp d2) := SOME (Start l1)
                      in ()
                      end
                    | SOME d1  => 
                      let
                        val () = (nextp d1) := SOME d2
                        val () = (prevp d2) := SOME (Elt d1)
                      in ()
                      end))
        val () = l2 := NONE
      in ()
      end

  fun insertLast (l : 'a t, e : 'a) : 'a cursor = 
      let
        val l2 = empty()
        val c = insert(l2, e)
        val () = append (l, l2)
      in 
        c
      end

  fun all (l : 'a t) : 'a cursor list = 
      let 
        fun loop (l, acc) = 
            (case !l
              of NONE => rev acc
               | SOME d => 
                 loop(nextp d, d :: acc))
      in loop (l, [])
      end

  fun foreach (l : 'a t, f : 'a -> unit) : unit = 
      let 
        fun loop l = 
            case !l
             of NONE => ()
              | SOME d => (f (data d); loop (nextp d))
      in loop l
      end

  fun toListMap (l : 'a t, f : 'a -> 'b) : 'b list = 
      List.map (all l, f o getVal)

  fun toListRev (l : 'a t) : 'a list = 
      let 
        fun loop (l, acc) = 
            (case !l
              of NONE => acc
               | SOME d => 
                 loop(nextp d, data d:: acc))
      in loop (l, [])
      end

  fun toList (l : 'a t) : 'a list = rev (toListRev l)

  val toListUnordered = toListRev

  fun toVectorRev (l : 'a t) : 'a vector = Vector.fromList (toListRev l)

  fun toVector (l : 'a t) : 'a vector = Vector.fromListRev (toListRev l)

  val toVectorUnordered = toVectorRev

  fun remove (node : 'a cursor) : unit = 
      let
        val pp = prevp node
        val np = nextp node
        val () = 
            case pp
             of ref NONE => ()
              | ref (SOME l) => 
                (pp := NONE;
                 (nodeNextp l) := !np;
                 case np
                  of ref NONE => ()
                   | ref (SOME c) => 
                     (
                      (prevp c) := SOME l;
                      np := NONE
                     )
                )
      in ()
      end

  fun link (n1 : 'a cursor, n2 : 'a cursor) : unit = 
      (
       nextp n1 := SOME n2;
       prevp n2 := SOME (Elt n1)
       )

  fun linkNode (n1 : 'a node, n2 : 'a cursor) : unit = 
      (
       nodeNextp n1 := SOME n2;
       prevp n2 := SOME n1
       )

  fun insertL (n1 : 'a cursor, e : 'a) : 'a cursor = 
      let
        val n2 = newData e
        val () = case !(prevp n1)
                  of SOME n3 => linkNode(n3, n2)
                   | NONE => ()
        val () = link (n2, n1)
      in n2
      end

  fun insertR (n1 : 'a cursor, e : 'a) : 'a cursor = 
      let
        val n2 = newData e
        val () = case !(nextp n1)
                  of SOME n3 => link(n2, n3)
                   | NONE => ()
        val () = link (n1, n2)
      in n2
      end

  fun next (n1 : 'a cursor) : 'a cursor option = !(nextp n1)

  fun prev (n1 : 'a cursor) : 'a cursor option = 
      case !(prevp n1)
       of NONE => NONE
        | SOME (Start _) => NONE
        | SOME (Elt data) => SOME data
                           
  fun layout (l : 'a t, f : 'a -> Layout.t) = 
      LayoutUtils.bracketSeq (List.map (all l, f o getVal))

  fun fromList (l : 'a list) : 'a t = 
      let
        val dl = empty()
        fun loop (c, l) = 
            (case l
              of [] => ()
               | a::l => loop(insertR (c, a), l))
        val () = 
            case l
             of [] => ()
              | a::l => loop(insert (dl, a), l)
      in dl
      end


end
(*
structure DList :> DLIST = 
struct


  type 'a ptr = 'a option ref

  fun $ r =
      case Ref.! r of
        NONE => Fail.fail ("Dereference of Null pointer")
      | SOME v => v

  datatype 'a data = 
           D of {prev : 'a node,
                 data : 'a,
                 next : 'a node}
  withtype 'a node = 'a data ptr
                  
  type 'a t = 'a node ref
  type 'a cursor = 'a data

  fun empty () : 'a t = ref (ref NONE)

  fun isEmpty (l : 'a t) : bool = not (isSome(!!l))

  fun newData (e : 'a) : 'a cursor = 
      let
        val prev = ref NONE
        val next = ref NONE
        val cursor = D {prev = prev,
                        data = SOME e,
                        next = next}
      in cursor
      end

  fun singleton (e : 'a) : 'a t = 
      let
        val l = ref NONE
        val p = ref NONE
        val n = ref NONE
        val cursor = D {prev = p,
                        data = e,
                        next = n}
        val () = l := cursor
        val () = p := cursor
        val () = n := cursor
      in ref l
      end

  fun prevp (D {prev, ...}) : 'a node ptr = prev
  fun nextp (D {next, ...}) : 'a data ptr = next

  fun data  (D {data, ...}) : 'a = data

  fun first (l : 'a t) : 'a cursor option = !!l
  fun last  (l : 'a t) : 'a cursor option = 
      (case !!l
        of SOME (D{prev, ...}) => SOME ($ prev)
         | NONE                => NONE)


  fun link (d1 as (D {next, ...}), 
            d2 as (D {prev, ...})) = 
      let
        val () = next := d2
        val () = prev := d1
      in ()
      end

  fun seq (l1, l2) = 
      (case (!l1, !l2)
        of (ref NONE, l)   => l1 := l
         | (l, ref NONE)   => l2 := l
         | (n1 as (ref (SOME d1)),
            n2 as (ref (SOME d2))) => 
           let
             val first = d1
             val midR  = $ (prevp d1)
             val midL  = d2
             val last  = $ (prevp d2)
             val () = link (midR, midL)
             val () = link (last, first)
             val () = n2 := SOME d1
           in ()
           end

  fun insert (l : 'a t, e : 'a) : 'a cursor = 
      let
        val s = singleton e
        val c = $!s
        val () = seq (s, l)
      in c
      end

  fun insertLast (l : 'a t, e : 'a) : 'a cursor = 
      let
        val s = singleton e
        val c = $!s
        val () = seq (l, s)
      in c
      end

  fun all (l : 'a t) : 'a cursor list = 
      (case !!l 
        of NONE => []
         | SOME d => 
           let
             val sentinal = nextp ($ (prevp d))
             fun loop (d, acc) = 
                 let
                   val acc = d::acc
                   val n = nextp d
                 in if n = sentinal then
                      rev acc
                    else => loop ($n, acc)
                 end
           in loop (d, [])
           end)

  fun foreach (l : 'a t, f : 'a -> unit) : unit = 
      (case !!l
        of NONE => ()
         | SOME d => 
           let 
             val sentinal = nextp ($ (prevp d))
             fun loop (d, acc) = 
                 let
                   val () = f (data d)
                   val n = nextp d
                 in if n = sentinal then ()
                    else loop ($n)
                 end
           in loop d
           end)

  fun toList (l : 'a t) : 'a list = List.map (all l, data)

  fun toVector (l : 'a t) : 'a vector = Vector.fromList (toList l)

  fun remove (node : 'a cursor) : unit = 
      let
        val pp = prevp node
        val np = nextp node
        val () = 
            case pp
             of ref NONE => ()
              | ref (SOME l) => 
                (pp := NONE;
                 (nodeNextp l) := !np;
                 case np
                  of ref NONE => ()
                   | ref (SOME c) => 
                     (
                      (prevp c) := SOME l;
                      np := NONE
                     )
                )
      in ()
      end

  fun link (n1 : 'a cursor, n2 : 'a cursor) : unit = 
      (
       nextp n1 := SOME n2;
       prevp n2 := SOME (Elt n1)
       )

  fun linkNode (n1 : 'a node, n2 : 'a cursor) : unit = 
      (
       nodeNextp n1 := SOME n2;
       prevp n2 := SOME n1
       )

  fun insertL (n1 : 'a cursor, e : 'a) : 'a cursor = 
      let
        val n2 = newData e
        val () = case !(prevp n1)
                  of SOME n3 => linkNode(n3, n2)
                   | NONE => ()
        val () = link (n2, n1)
      in n2
      end

  fun insertR (n1 : 'a cursor, e : 'a) : 'a cursor = 
      let
        val n2 = newData e
        val () = case !(nextp n1)
                  of SOME n3 => link(n2, n3)
                   | NONE => ()
        val () = link (n1, n2)
      in n2
      end

  fun next (n1 : 'a cursor) : 'a cursor option = !(nextp n1)

  fun prev (n1 : 'a cursor) : 'a cursor option = 
      case !(prevp n1)
       of NONE => NONE
        | SOME (Start _) => NONE
        | SOME (Elt data) => SOME data
                           
  fun getVal (D{data, ...} : 'a cursor) : 'a = data

  fun layout (l : 'a t, f : 'a -> Layout.t) = 
      LayoutUtils.bracketSeq (List.map (all l, f o getVal))

  fun fromList (l : 'a list) : 'a t = 
      let
        val dl = empty()
        fun loop (c, l) = 
            (case l
              of [] => ()
               | a::l => loop(insertR (c, a), l))
        val () = 
            case l
             of [] => ()
              | a::l => loop(insert (dl, a), l)
      in dl
      end

end
*)

signature STATS = 
sig
  type t

  val new : unit -> t

  val addToStat : t * string * int -> unit
  val incStat : t * string -> unit
  val getStat : t * string -> int
  val hasStat : t * string -> bool
  val newStat : t * string * string -> unit
  val fromList : (string * string) list -> t
 (* Add all statistics in s2 to s1
  * merge (s1, s2) => 
  *   For every statistic s:
  *     if s was in s2 and not s1, it is added to s1, with s1.s = s2.s
  *     if s was in s2 and s1, s1.s is incremented by s2.s
  *     Any subsequent increment of s2.s also increments s1.s
  *       (increments to s1.s do not affect s2.s)
  * Currently, new statistics subsequently added to s2 will not be added
  * to s1.  This functionality can be added if desired.
  *)
  val merge : t * t -> unit
  (* Push scope of stats
   * push s =>
   *   Return a new statistics sets with every statistic of s but with count 0
   *   Any subsequent increment of new stat also increments old stat
   *   (But no vice versa.)
   * Currently, new statistics subsequently added to the new set will not be
   * added to the old set.  This functionality can be added if desired.
   *)
  val push : t -> t
  val layout : t -> Layout.t
  val report : t -> unit
end

structure Stats :> STATS = 
struct
  structure ISD = ImpStringDict
  datatype count = C of (int ref) * (count list ref)
           
  type t = (string * count) ISD.t

  fun get (d, s) = 
      (case ISD.lookup(d, s) 
        of SOME (cmt, c) => c
         | NONE => Fail.fail ("stats.sml",
                              "get",
                              "unknown stat " ^ s))
  fun addToStat (d, s, n) = 
      let
        val C (r, _) = get(d, s)
      in r := !r + n
      end

  fun incStat (d, s) = addToStat(d, s, 1)

  fun sumCount (C (r, counts)) = 
      List.fold (!counts, !r, fn (c, s) => s + sumCount c)
  fun getStat (d, s) = sumCount(get(d, s))
  fun hasStat (d, s) = ISD.contains(d, s)

  fun new () = ISD.empty ()
  fun newStat (d, s, cmt) = 
      let
        val c = C (ref 0, ref [])
      in ISD.insert(d, s, (cmt, c))
      end

  fun fromList l = 
      let
        val d = new () 
        val () = List.foreach (l, fn (s, cmt) => newStat (d, s, cmt))
      in d
      end

  fun merge (s1, s2) = 
      let
        fun help (s, (cmt, count)) = 
            case (ISD.lookup (s1, s))
             of SOME (cmt, C (_, c)) => c := count :: !c
              | NONE => ISD.insert (s1, s, (cmt, C (ref 0, ref [count])))
        val () = List.foreach (ISD.toList s2, help)
      in ()
      end

  fun push s1 =
      let
        fun doOne (_, (cmt, C (_, c))) =
            let
              val count = C (ref 0, ref [])
              val () = c := count :: !c
            in (cmt, count)
            end
        val s2 = ISD.copyWith (s1, doOne)
      in s2
      end

  fun layoutOne (s, (cmt, r)) = 
      let
        val i = sumCount r
        val lo = 
            if i > 0 then 
              SOME (Layout.seq[Int.layout i, 
                               Layout.str " ", 
                               Layout.str cmt])
            else
              NONE
      in lo
      end
  fun layout d = Layout.align ((Layout.str "Statistics:")::
                               List.keepAllMap (ISD.toList d, layoutOne))
  fun report d = LayoutUtils.printLayout(layout d)
end


signature ImpQueue = 
sig
  type 'a t
  val new : unit -> 'a t
  val fromList : 'a list -> 'a t
  val enqueue : 'a t * 'a -> unit
  val enqueueList : 'a t * 'a list -> unit
  val dequeue : 'a t -> 'a
  val head : 'a t -> 'a
  val peek : 'a t -> 'a option
  val isEmpty : 'a t -> bool
end

structure ImpQueue :> ImpQueue = 
struct
  type 'a t = 'a Queue.queue

  val new = Queue.mkQueue

  fun enqueueList (q, l) = 
      let
        val () = List.foreach (l, fn a => Queue.enqueue(q, a))
      in ()
      end

  fun fromList l = 
      let
        val q = new() 
        val () = enqueueList(q, l)
      in q
      end

  val enqueue = Queue.enqueue

  val dequeue = Queue.dequeue
  val head = Queue.head
  val peek = Queue.peek
  val isEmpty = Queue.isEmpty
end


(* Fixed size imperative bit sets *)
signature IMP_BIT_SET = sig
    type t
    val new : Int32.t -> t
    val copy : t -> t
    val fromList   : Int32.t * Int32.t list -> t
    val fromVector : Int32.t * Int32.t vector -> t
    val insertList   : t * Int32.t list -> unit
    val insertVector : t * Int32.t vector -> unit
   (* Return elements in increasing order *)
    val toList   : t -> Int32.t list
    val toVector : t -> Int32.t vector
    val isEmpty : t -> bool
    val count   : t -> int
    val equal : t * t -> bool
    val isSubset : t * t -> bool
    val insert   : t * Int32.t -> unit
    val remove   : t * Int32.t -> unit
    (* binary operators modify first set *)
    val union        : t * t -> unit
    val intersection : t * t -> unit
    val difference   : t * t -> unit
    val complement   : t -> unit
    val member       : t * Int32.t -> bool
    val forall       : t * (Int32.t -> bool) -> bool
    val exists       : t * (Int32.t -> bool) -> bool
    val partition    : t * (Int32.t -> bool) -> {no: t, yes: t}
    val foreach : t * (Int32.t -> unit) -> unit
    val keepAll : t * (Int32.t -> bool) -> unit
    val fold : t * 'b * (Int32.t * 'b -> 'b) -> 'b
    val getAny : t -> Int32.t option
    val layout : t * (Int32.t -> Layout.t) -> Layout.t
end;


(* Fixed size imperative bit sets *)
structure ImpBitSet :> IMP_BIT_SET = 
struct
  structure BA = BitArray
  type t = BA.array

  val new : Int32.t -> t =
    fn i => BA.array (i, false)

  val copy : t -> t = 
    fn s => BA.extend0 (s, BA.length s)

  val insert   : t * Int32.t -> unit = BA.setBit

  val member       : t * Int32.t -> bool = BA.sub

  val fromList   : Int32.t * Int32.t list -> t = BA.bits

  val insertList   : t * Int32.t list -> unit = 
   fn (s, l) =>
      List.foreach (l, fn i => insert (s, i))

  val insertVector : t * Int32.t vector -> unit = 
   fn (s, l) =>
      Vector.foreach (l, fn i => insert (s, i))

  val fromVector : Int32.t * Int32.t vector -> t = 
   fn (i, elts) =>
      let
        val s = new i
        val () = insertVector (s, elts)
      in s
      end

  val toList   : t -> Int32.t list = BA.getBits

  val toVector : t -> Int32.t vector = Vector.fromList o toList

  val isEmpty : t -> bool = BA.isZero

  val fold : t * 'b * (Int32.t * 'b -> 'b) -> 'b = 
   fn (s, a, f) => 
      BA.foldli (fn (i, b, a) => if b then f (i, a) else a) a s

  val count : t -> int = 
   fn s => fold (s, 0, fn (_, c) => c+1)
      
  val equal : t * t -> bool = BA.equal

  val remove   : t * Int32.t -> unit = BA.clrBit

  val foreach : t * (Int32.t -> unit) -> unit = 
   fn (s, f) => 
      BA.appi (fn (i, b) => if b then f i else ()) s

  val forall       : t * (Int32.t -> bool) -> bool = 
   fn (s, f) => 
      let
        val length = BA.length s
        val rec loop = 
         fn i =>
            if i = length then true
            else BA.sub (s, i) andalso loop(i+1)
      in loop 0
      end

  val isSubset : t * t -> bool = 
      fn (s1, s2) => BA.isZero(BA.andb(s1, BA.notb s2, BA.length s1))
      
  (* binary operators modify first set *)
  val union        : t * t -> unit = 
      fn (s1, s2) => BA.union s1 s2

  val intersection : t * t -> unit = 
      fn (s1, s2) => BA.intersection s1 s2

  val difference   : t * t -> unit = 
      fn (s1, s2) => foreach (s2, fn i => (remove (s1, i)))

  val complement   : t -> unit = BA.complement
      
  val exists       : t * (Int32.t -> bool) -> bool = 
   fn (s, f) => 
      let
        val length = BA.length s
        val rec loop = 
         fn i =>
            if i = length then false
            else BA.sub (s, i) orelse loop(i+1)
      in loop 0
      end

  val partition    : t * (Int32.t -> bool) -> {no: t, yes: t} = 
   fn (s, p) => 
      let
        val l = BA.length s
        val yes = new l
        val no = new l
        val help = 
         fn i => 
            if p i then
               insert (yes, i)
            else
              insert (no, i)
        val () = 
            foreach (s, help)
      in {yes = yes, 
          no  = no}
      end

  val keepAll : t * (Int32.t -> bool) -> unit = 
      fn (s, p) => 
         BA.modifyi (fn (i, b) => b andalso (p i)) s

  val getAny : t -> Int32.t option = 
   fn s => 
      let
        val length = BA.length s
        val rec loop = 
         fn i => 
            if i = length then 
              NONE
            else if BA.sub (s, i) then 
              SOME i
            else 
              loop(i+1)
      in loop 0
      end

  val layout : t * (Int32.t -> Layout.t) -> Layout.t = 
   fn (s, lf) =>
      let
        val elts = toList s
        val l = List.layout lf elts
      in l
      end
end      

signature EQUIVALENCE_CLASS = 
sig
  type 'a t
  val new   : 'a -> 'a t
  (* Returns true iff previously disjoint *)
  val join  : 'a t * 'a t -> bool
  (* joinWith (a, b, f) = joins a and b.  If a and b were not already equal, 
   * it then sets the contents to be f(ad, bd), where ad and bd are 
   * the original contents of and b.
   *)
  val joinWith : 'a t * 'a t * ('a * 'a -> 'a) -> bool
  val equal : 'a t * 'a t -> bool
  val set   : 'a t * 'a -> unit
  val get   : 'a t -> 'a
end

structure EquivalenceClass :> EQUIVALENCE_CLASS = 
struct

  datatype 'a tS = 
           Root of 'a * int
         | Child of 'a t
  withtype 'a t = 'a tS ref

  val new   : 'a -> 'a t = 
   fn a => ref (Root (a, 0))
           
  val rec find  : 'a t -> 'a t * 'a * int = 
   fn a => 
      (case !a
        of Root (d, i) => (a, d, i)
         | Child p => 
           let
             val (p, d, i) = find p
             val () = a := Child p
           in (p, d, i)
           end)

  val equal : 'a t * 'a t -> bool = 
   fn (a, b) => 
      let
        val (a, _, _) = find a
        val (b, _, _) = find b
      in
        a = b
      end

  val set   : 'a t * 'a -> unit = 
   fn (a, d) => 
      let
        val (a, _, ar) = find a
      in a := Root (d, ar)
      end

  val get   : 'a t -> 'a = 
   fn a => 
      let
        val (_, d, _) = find a
      in d
      end

  val join  : 'a t * 'a t -> bool = 
   fn (a, b) => 
      let
        val (a, ad, ar) = find a
        val (b, bd, br) = find b
      in
        if (a = b) then 
          false
        else
          let
            val (p, c, r) = 
                case Int.compare (ar, br)
                 of LESS    => (b, a, br)
                  | GREATER => (a, b, ar)
                  | EQUAL   => (a, b, br+1)
            val () = p := Root(ad, r)
            val () = c := Child p
          in true
          end
      end

  val joinWith : 'a t * 'a t * ('a * 'a -> 'a) -> bool = 
   fn (a, b, f) => 
      let
        val ad = get a
        val bd = get b
        val b = join (a, b)
        val () = if b then 
                   set (a, f (ad, bd))
                 else
                   ()

      in b
      end      

end;

signature POLY_LATTICE = 
sig
  type 'a t

  val top : 'a t
  val bot : 'a t
  val elt : 'a -> 'a t 

  val isTop : 'a t -> bool
  val isBot : 'a t -> bool
  val isElt : 'a t -> bool

  val get : 'a t -> 'a option

  val join : {lub : 'a * 'a -> 'a option,
              mkTop : 'a -> 'a} 
             -> ('a t * 'a t -> 'a t)

  val layout : ('a -> Layout.t) -> ('a t -> Layout.t)
  val equal : ('a * 'a -> bool) -> ('a t * 'a t -> bool)
end;

structure PolyLattice :> POLY_LATTICE = 
struct
  datatype 'a t = 
           Top 
         | Bot 
         | Elt of 'a

  val top = Top
  val bot = Bot
  val elt = Elt

  val isTop = fn t => case t of Top => true | _ => false
  val isBot = fn t => case t of Bot => true | _ => false
  val isElt = fn t => case t of Elt _ => true | _ => false


  val get = 
   fn t => 
      (case t 
        of Elt e => SOME e
         | _ => NONE)

  val rec topify = 
   fn mkTop => 
   fn t => 
      (case t
        of Top => Top
         | Bot => Top
         | Elt t => (mkTop t;Top))
      
  val rec join = 
   fn {lub, mkTop} => 
   fn (t1, t2) => 
      case (t1, t2)
       of (Top, _) => topify mkTop t2
        | (_, Top) => topify mkTop t1
        | (Bot, _) => t2
        | (_, Bot) => t1
        | (Elt e1, Elt e2) => 
          (case lub (e1, e2)
            of SOME e => Elt e
             | NONE => (topify mkTop t1;
                        topify mkTop t2))

  local 
    structure L = Layout
  in
  val layout = 
      (fn layoutElt =>
          (fn t => 
              (case t
                of Top => L.str "_T_"
                 | Bot => L.str "_B_"
                 | Elt e => L.seq [L.str "E(", layoutElt e, 
                                   L.str ")"])))
  end

  val equal = 
   fn eqT =>
   fn (t1, t2) => 
      (case (t1, t2) 
        of (Top, Top) => true
         | (Bot, Bot)  => true
         | (Elt e1, Elt e2) => eqT (e1, e2)
         | _ => false)
end

(* Semi-Lattices, and functors for injecting partially ordered sets into 
 * bounded semi-lattices.
 *)
signature LATTICE = 
sig
  type t
  type element

  val top : t
  val bot : t
  val elt : element -> t 

  val isTop : t -> bool
  val isBot : t -> bool
  val isElt : t -> bool

  val get : t -> element option

  val join : t * t -> t

  val layout : (element -> Layout.t) -> (t -> Layout.t)
  val equal : (element * element -> bool) -> (t * t -> bool)
end;

(* Base lattice functor, which supports recursively defined lattice
 * structure.
 *)
functor RecLatticeFn(type 'a element
                     val mkTop : 'a * ('a -> 'a) -> 'a element -> unit
                     val lub : (('a * 'a) -> 'a) -> 
                                'a element * 'a element -> 'a element option)
        :>
         sig
           type t
           type element = t element
                
           val top : t
           val bot : t
           val elt :  element -> t 
                                 
           val isTop : t -> bool
           val isBot : t -> bool
           val isElt : t -> bool
                            
           val get : t -> element option
                          
           val join : t * t -> t

           val layout : (element -> Layout.t) -> (t -> Layout.t)
           val equal : (element * element -> bool) -> (t * t -> bool)
         end
  =
struct
  datatype t = 
           Top 
         | Bot 
         | Elt of t element
  type element = t element
  val top = Top
  val bot = Bot
  val elt = Elt

  val isTop = fn t => case t of Top => true | _ => false
  val isBot = fn t => case t of Bot => true | _ => false
  val isElt = fn t => case t of Elt _ => true | _ => false


  val get = 
   fn t => 
      (case t 
        of Elt e => SOME e
         | _ => NONE)

  val rec topify = 
      fn t => 
         (case t
           of Top => Top
            | Bot => Top
            | Elt t => (mkTop (Top, topify) t;Top))

  val rec join = 
   fn (t1, t2) => 
      case (t1, t2)
       of (Top, _) => topify t2
        | (_, Top) => topify t1
        | (Bot, _) => t2
        | (_, Bot) => t1
        | (Elt e1, Elt e2) => 
          (case lub join (e1, e2)
            of SOME e => Elt e
             | NONE => (topify t1;
                        topify t2))

  local 
    structure L = Layout
  in
  val layout = 
      (fn layoutElt =>
          (fn t => 
              (case t
                of Top => L.str "_T_"
                 | Bot => L.str "_B_"
                 | Elt e => L.seq [L.str "E(", layoutElt e, 
                                   L.str ")"])))
  end

  val equal = 
   fn eqT =>
   fn (t1, t2) => 
      (case (t1, t2) 
        of (Top, Top) => true
         | (Bot, Bot)  => true
         | (Elt e1, Elt e2) => eqT (e1, e2)
         | _ => false)
end

(* Basic non-recursive lattice
 *)
functor LatticeFn(type element
                  val mkTop : element -> unit
                  val lub : element * element -> element option)
        :> LATTICE where type element = element = 
struct
  structure Lat = RecLatticeFn (type 'a element = element
                                val mkTop = fn _ => mkTop
                                val lub = fn _ => lub)
  open Lat
end;

(* Turn equality into a degenerate lub
 * for use in creating flat latttices 
 *)
functor MkFlatFuns(type element
                   val mkTop : element -> unit
                   val equal : element * element -> bool) 
: sig
    type element = element
    val mkTop : element -> unit
    val lub : element * element -> element option
  end = 
struct
  type element = element
  val mkTop = mkTop
  val lub = 
   fn (a, b) => 
      if equal (a, b) then SOME a else NONE
end;

(* Make a flat lattice, where lub(a, b) exists iff a = b
 *)
functor FlatLatticeFn(type element
                      val mkTop : element -> unit
                      val equal : element * element -> bool) 
        :> LATTICE where type element = element = 
struct
  structure Lat = LatticeFn(MkFlatFuns(type element = element
                                       val mkTop = mkTop
                                       val equal = equal))
  open Lat
end;

(* A lattice whose elements consist of vectors of lattice elements. 
 * The join of two equal length vectors is  the vector
 * of joins of their elements, and similarly for meets.  Unequal lengths 
 * meet at bottom and join at top. 
 *)
functor LatticeVectorLatticeFn(structure Lattice : LATTICE)
        :> LATTICE where type element = Lattice.t Vector.t = 
struct
  val mkTop = 
   fn v => Vector.foreach (v, fn a => ignore (Lattice.join (a, Lattice.top)))

  val lub = 
   fn (a, b) => 
      if Vector.length a = Vector.length b then
        SOME (Vector.map2 (a, b, Lattice.join))
      else 
        NONE

  structure Lat = LatticeFn(type element = Lattice.t Vector.t
                            val mkTop = mkTop
                            val lub = lub)
  open Lat
end;


(* A lattice whose elements consists of optional values.
* NONE and SOME are unrelated, SOMEs are related according to the
* meet/join of their contents *)
functor OptionLatticeFn(type element
                        val mkTop : element -> unit
                        val lub : element * element -> element option)
        :> LATTICE where type element = element option =
struct
  val mkTop = 
   fn a =>
      case a
       of SOME v => mkTop v
        | NONE => ()

  val lub = 
      (fn (a, b) => 
          (case (a, b)
            of (NONE, NONE) => SOME NONE
             | (SOME a, SOME b) => 
               Option.map(lub (a, b), SOME)
             | _ => NONE))

  structure Lattice = LatticeFn(type element = element option
                                val mkTop = mkTop
                                val lub = lub)
  open Lattice
end;

(* A lattice whose elements are optional values, where the components
 * of the option type are related only by equality
 *)
functor FlatOptionLatticeFn(type element
                            val mkTop : element -> unit
                            val equal : element * element -> bool)
        :> LATTICE where type element = element option =
struct
  structure Lat = OptionLatticeFn(MkFlatFuns(type element = element
                                             val mkTop = mkTop
                                             val equal = equal))
  open Lat
end

(* Build functional get/set methods for a record type.  To use,
 * define functions mapping a record type into and out of a nested 
 * tuple type, and pass these to the mk function of the appropriate arity.  
 * The result is a nested tuple of (get, set) tuples, with (set, get) field 
 * of the nested tuple corresponding to the get/set method for the record
 * field mapped to the corresponding position by the record isomorphism.  
 * Example:
 *
 * datatype t = T of {a : int, b : bool, c : int}
 *
 * val ((setA, getA),
 *      ((setB, getB),
 *       ((setC, getC)))) = 
 *    FunctionalUpdate.mk3 (fn (T{a, b, c}) => (a, (b, c)),
 *                          fn (a, (b, c)) => T{a = a, b =b, c = })
 * *)
signature FUNCTIONAL_UPDATE =
sig
  type ('record, 'tuple, 'ops) builder = 
       ('record -> 'tuple) * ('tuple -> 'record) 
       -> 'ops

  type ('record, 'elt) ops = 
       ('record * 'elt -> 'record) * 
       ('record -> 'elt)


  type ('r, 'a1) ops1                                    = ('r, 'a1) ops
  type ('r, 'a1, 'a2) ops2                               = ('r, 'a1) ops * ('r, 'a2) ops1
  type ('r, 'a1, 'a2, 'a3) ops3                          = ('r, 'a1) ops * ('r, 'a2, 'a3) ops2
  type ('r, 'a1, 'a2, 'a3, 'a4) ops4                     = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4) ops3
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5) ops5                = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5) ops4
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6) ops6           = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6) ops5
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7) ops7      = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7) ops6
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8) ops8 = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8) ops7
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9) ops9
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9) ops8
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10) ops10
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10) ops9
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11) ops11
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9,'a10, 'a11) ops10
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11, 'a12) ops12
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9,'a10, 'a11, 'a12) ops11
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11, 'a12, 'a13) ops13
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9,'a10, 'a11, 'a12, 'a13) ops12
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11, 'a12, 'a13, 'a14) ops14
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9,'a10, 'a11, 'a12, 'a13, 'a14) ops13

  val mk1 : ('r, 'a1,                                              ('r, 'a1) ops1                              ) builder
  val mk2 : ('r, 'a1 * 'a2,                                        ('r, 'a1, 'a2) ops2                         ) builder
  val mk3 : ('r, 'a1 * ('a2 * 'a3),                                ('r, 'a1, 'a2, 'a3) ops3                    ) builder
  val mk4 : ('r, 'a1 * ('a2 * ('a3 * 'a4)),                        ('r, 'a1, 'a2, 'a3, 'a4) ops4               ) builder
  val mk5 : ('r, 'a1 * ('a2 * ('a3 * ('a4 * 'a5))),                ('r, 'a1, 'a2, 'a3, 'a4, 'a5) ops5          ) builder
  val mk6 : ('r, 'a1 * ('a2 * ('a3 * ('a4 * ('a5 * 'a6)))),        ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6) ops6     ) builder
  val mk7 : ('r, 'a1 * ('a2 * ('a3 * ('a4 * ('a5 * ('a6 * 'a7))))),('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7) ops7) builder
  val mk8 : ('r, 'a1 * ('a2 * ('a3 * ('a4 * ('a5 * ('a6 * ('a7 * 'a8)))))), 
             ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8) ops8     ) builder
  val mk9 : ('r, 'a1 * ('a2 * ('a3 * ('a4 * ('a5 * ('a6 * ('a7 * ('a8 * 'a9))))))), 
             ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9) ops9) builder
  val mk10 : 
      ('r, 
       'a1 * ('a2 * ('a3 * ('a4 * ('a5 * ('a6 * ('a7 * ('a8 * ('a9 * 'a10)))))))), 
       ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10) ops10) builder
  val mk11 : 
      ('r, 
       'a1 * ('a2 * ('a3 * ('a4 * ('a5 * ('a6 * ('a7 * ('a8 * ('a9 * ('a10 * 'a11))))))))), 
       ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11) ops11) builder
  val mk12 : 
      ('r, 
       'a1 * ('a2 * ('a3 * ('a4 * ('a5 * ('a6 * ('a7 * ('a8 * ('a9 * ('a10 * ('a11 * 'a12)))))))))), 
       ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11, 'a12) ops12) builder
  val mk13 : 
      ('r, 
       'a1 * ('a2 * ('a3 * ('a4 * ('a5 * ('a6 * ('a7 * ('a8 * ('a9 * ('a10 * ('a11 * ('a12 * 'a13))))))))))), 
       ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11, 'a12, 'a13) ops13) builder
  val mk14 : 
      ('r, 
       'a1 * ('a2 * ('a3 * ('a4 * ('a5 * ('a6 * ('a7 * ('a8 * ('a9 * ('a10 * ('a11 * ('a12 * ('a13 * 'a14)))))))))))),
       ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11, 'a12, 'a13, 'a14) ops14) builder

end

structure FunctionalUpdate :> FUNCTIONAL_UPDATE = 
struct

  type ('record, 'tuple, 'ops) builder = 
       ('record -> 'tuple) * ('tuple -> 'record) 
       -> 'ops

  type ('record, 'elt) ops = 
       ('record * 'elt -> 'record) * 
       ('record -> 'elt)

  type ('r, 'a1) ops1                                    = ('r, 'a1) ops
  type ('r, 'a1, 'a2) ops2                               = ('r, 'a1) ops * ('r, 'a2) ops1
  type ('r, 'a1, 'a2, 'a3) ops3                          = ('r, 'a1) ops * ('r, 'a2, 'a3) ops2
  type ('r, 'a1, 'a2, 'a3, 'a4) ops4                     = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4) ops3
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5) ops5                = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5) ops4
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6) ops6           = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6) ops5
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7) ops7      = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7) ops6
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8) ops8 = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8) ops7
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9) ops9
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9) ops8
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10) ops10
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9,'a10) ops9
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11) ops11
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9,'a10, 'a11) ops10
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11, 'a12) ops12
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9,'a10, 'a11, 'a12) ops11
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11, 'a12, 'a13) ops13
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9,'a10, 'a11, 'a12, 'a13) ops12
  type ('r, 'a1, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9, 'a10, 'a11, 'a12, 'a13, 'a14) ops14
    = ('r, 'a1) ops * ('r, 'a2, 'a3, 'a4, 'a5, 'a6, 'a7, 'a8, 'a9,'a10, 'a11, 'a12, 'a13, 'a14) ops13


  type ('record, 'elts, 'setters) mker = 
       ('record -> ('elts -> 'record) * 'elts)
       -> 'setters

  val mk1' : ('r, 'e, ('r, 'e) ops) mker = 
   fn split => 
      let
        val set1 = 
         fn (r, a) => 
            let
              val (t2r, _) = split r
            in t2r a
            end
        val get1 = #2 o split
      in (set1, get1)
      end


  val mker 
      : ('r,      'e,                  's) mker ->
        ('r, 'f * 'e, (('r, 'f) ops) * 's) mker = 
   fn mk => 
   fn split => 
      let
        val set1 = 
         fn (r, a) => 
            let
              val (t2r, (_, b)) = split r
            in t2r (a, b)
            end
      val get1 = #1 o #2 o split
      val split = 
       fn r => 
          let
            val (t2r, (a, b)) = split r
            val t2r = fn b => t2r (a, b)
          in (t2r, b)
          end
      val set2 = mk split
    in ((set1, get1), set2)
    end

  val mk2' = fn args => mker mk1' args
  val mk3' = fn args => mker mk2' args
  val mk4' = fn args => mker mk3' args
  val mk5' = fn args => mker mk4' args
  val mk6' = fn args => mker mk5' args
  val mk7' = fn args => mker mk6' args
  val mk8' = fn args => mker mk7' args
  val mk9' = fn args => mker mk8' args
  val mk10' = fn args => mker mk9' args
  val mk11' = fn args => mker mk10' args
  val mk12' = fn args => mker mk11' args
  val mk13' = fn args => mker mk12' args
  val mk14' = fn args => mker mk13' args
                        
  val mk1 = fn (r2t, t2r) =>  mk1' (fn a => (t2r, r2t a))
  val mk2 = fn (r2t, t2r) =>  mk2' (fn a => (t2r, r2t a))
  val mk3 = fn (r2t, t2r) =>  mk3' (fn a => (t2r, r2t a))
  val mk4 = fn (r2t, t2r) =>  mk4' (fn a => (t2r, r2t a))
  val mk5 = fn (r2t, t2r) =>  mk5' (fn a => (t2r, r2t a))
  val mk6 = fn (r2t, t2r) =>  mk6' (fn a => (t2r, r2t a))
  val mk7 = fn (r2t, t2r) =>  mk7' (fn a => (t2r, r2t a))
  val mk8 = fn (r2t, t2r) =>  mk8' (fn a => (t2r, r2t a))
  val mk9 = fn (r2t, t2r) =>  mk9' (fn a => (t2r, r2t a))
  val mk10 = fn (r2t, t2r) =>  mk10' (fn a => (t2r, r2t a))
  val mk11 = fn (r2t, t2r) =>  mk11' (fn a => (t2r, r2t a))
  val mk12 = fn (r2t, t2r) =>  mk12' (fn a => (t2r, r2t a))
  val mk13 = fn (r2t, t2r) =>  mk13' (fn a => (t2r, r2t a))
  val mk14 = fn (r2t, t2r) =>  mk14' (fn a => (t2r, r2t a))

end

signature BACK_PATCH = 
sig
  type 'a t
  val new : unit -> 'a t
  val fill : 'a t * 'a -> unit
  val get : 'a t -> 'a

  type ('a, 'b) func = ('a -> 'b) t
  val apply : ('a, 'b) func -> ('a -> 'b)
end
structure BackPatch :> BACK_PATCH = 
struct
  type 'a t = 'a option ref

  val new = 
   fn () => ref NONE
  val fill = 
   fn (b, a) => 
      (case !b
        of SOME _ => Fail.fail ("utils.sml", "fill", "Already filled")
         | NONE => b := SOME a)
  val get = 
   fn b => 
      (case !b
        of SOME a => a
         | NONE => Fail.fail ("utils.sml", "get", "Not yet filled"))

  type ('a, 'b) func = ('a -> 'b) t

  val apply = 
   fn f => fn a => get f a

end
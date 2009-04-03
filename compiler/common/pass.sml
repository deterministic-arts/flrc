(* The Intel P to C/Pillar Compiler *)
(* Copyright (C) Intel Corporation, October 2006 *)

(* Pass control file *)

(* Provides for describing passes and for performing them *)

signature PASS_DATA =
sig
  type t
  val getConfig : t -> Config.t
  val getStats : t -> Stats.t
  val getLevel : t -> int
  val click : t * string -> unit
  val clickN : t * string * int -> unit
  val mk : Config.t * (string * string) list -> t
  val push : t -> t
  val report : t * string -> unit
end;

structure PassData :> PASS_DATA =
struct

  datatype t = PD of {config : Config.t, stats : Stats.t, level : int}

  fun getConfig (PD {config, ...}) = config
  fun getStats (PD {stats, ...}) = stats
  fun getLevel (PD {level, ...}) = level

  fun click (d, s) = Stats.incStat (getStats d, s)

  fun clickN (d, s, n) = Stats.addToStat (getStats d, s, n)

  fun mk (config, stats) =
      let
        val stats = Stats.fromList stats
        val d = PD {config = config, stats = stats, level = 0}
      in d
      end

  fun push (PD {config, stats, level}) =
      PD {config = config, stats = Stats.push stats, level = level + 1}

  fun report (pd, passname) = 
      if Config.reportEnabled(getConfig pd, passname) then
        Stats.report (getStats pd)
      else
        ()

end;

signature PASS =
sig
  type ('a, 'b) t
  type ('a, 'b) processor
  type 'a irHelpers = {
       printer : 'a * Config.t -> Layout.t,
       stater  : 'a * Config.t -> Layout.t
  }
  type ('a, 'b) description = {
       name        : string,
       description : string,
       inIr        : 'a irHelpers,
       outIr       : 'b irHelpers,
       mustBeAfter : ('a, 'b) t list,
       stats       : (string * string) list
  }
  type ('a, 'b) associates = {
       controls  : Config.Control.control list,
       debugs    : Config.Debug.debug list,
       features  : Config.Feature.feature list,
       subPasses : ('a, 'b) t list
  }
  val unitHelpers : unit irHelpers
  val mkCompulsoryPass : ('a, 'b) description
                         * ('a, 'b) associates
                         * ('a * PassData.t -> 'b) 
                         -> ('a, 'b) t
  val mkOptPass : ('a, 'a) description
                  * ('a, 'a) associates
                  * ('a * PassData.t -> 'a)
                  -> ('a, 'a) t
  val mkOptFullPass : ('a, 'a) description
                      * ('a, 'a) associates
                      * ('a * PassData.t * string -> 'a)
                      -> ('a, 'a) t
  val mkFilePass : ('a, 'b) description
                   * ('a, 'b) associates
                   * ('a * PassData.t * string -> 'b) 
                   -> ('a, 'b) t
  val getDescription : ('a, 'b) t -> ('a, 'b) description
  val getName : ('a, 'b) t -> string
  val getDescriptionS : ('a, 'b) t -> string
  val getMustBeAfter : ('a, 'b) t -> ('a, 'b) t list
  val getStats : ('a, 'b) t -> (string * string) list
  val getAssociates : ('a, 'b) t -> ('a, 'b) associates
  val isOptional : ('a, 'b) t -> bool
  (* check (ps1, ps2):
   *   ps1 is a list of possible passes
   *   ps2 is a list of passes to run
   *   check that each compulsory pass is in ps2
   *   check that each pass in ps2 comes after the passes it is supposed to
   *)
  val check : ('a, 'b) t list * ('a, 'b) t list -> bool
  val doPass : ('a, 'b) t -> ('a, 'b) processor
  val doPassWrap : ('a, 'b) t * ('c -> 'a) * ('b -> 'd) -> ('c, 'd) processor
  val doSubPass : ('a, 'b) t -> ('a, 'b) processor
  exception Done
  val stopAt : Config.stopPoint -> ('a, 'a) processor
  val >> : ('a, 'b) processor * ('b, 'c) processor -> ('a, 'c) processor
  val apply : ('a, 'b) processor -> PassData.t * string * 'a -> 'b
  val startFile : Config.t * string -> unit
  val endFile : Config.t * string -> unit
  val doPassPart : Config.t * string * (unit -> 'a) -> 'a
  val run :
      Config.t * (Config.t * string -> unit) * string * string list -> unit
end;

structure Pass :> PASS =
struct

  type 'a irHelpers = {
       printer : 'a * Config.t -> Layout.t,
       stater  : 'a * Config.t -> Layout.t
  }

  datatype ('a, 'b) t = P of {
           description : ('a, 'b) description,
           associates  : ('a, 'b) associates,
           optional    : bool,
           f           : PassData.t * string * 'a -> 'b
  }
  withtype ('a, 'b) associates = {
       controls  : Config.Control.control list,
       debugs    : Config.Debug.debug list,
       features  : Config.Feature.feature list,
       subPasses : ('a, 'b) t list
  }
  and ('a, 'b) description = {
      name        : string,
      description : string,
      inIr        : 'a irHelpers,
      outIr       : 'b irHelpers,
      mustBeAfter : ('a, 'b) t list,
      stats       : (string * string) list
  }

  datatype ('a, 'b) processor = T of PassData.t * string * 'a -> 'b

  val unitHelpers = {
      printer = fn _ => Layout.str "Success!",
      stater  = fn _ => Layout.empty
  }

  fun getDescription (P {description, ...}) = description
  fun getName  p = #name (getDescription p)
  fun getDescriptionS p = #description (getDescription p)
  fun getInIr p = #inIr (getDescription p)
  fun getOutIr p = #outIr (getDescription p)
  fun getMustBeAfter p = #mustBeAfter (getDescription p)
  fun getStats p = #stats (getDescription p)
  fun getAssociates (P {associates, ...}) = associates
  fun isOptional (P {optional, ...}) = optional
  fun getF (P {f, ...}) = f

  structure Chat = ChatF (type env = Config.t
                          fun extract x = x
                          val name = "Toplevel"
                          val indent = 0)

  fun bold s = 
      let
        val s = "========== " ^ s
        val s = StringCvt.padRight #"=" 60 (s ^ " ")
      in s
      end

  fun startFile (config, fname) =
      Chat.log0 (config, bold ("Starting File " ^ fname))

  fun endFile (config, fname) =
      Chat.log0 (config, bold ("Finished File " ^ fname))

  fun doLayout (config, msg, l) =
      let
        val () = Chat.log0 (config, bold msg)
        val () = LayoutUtils.printLayout l
      in ()
      end

  fun doPass p =
   fn (pd, basename, arg) =>
     let
       val config = PassData.getConfig pd
       val name = getName p
       val inIr = getInIr p
       val outIr = getOutIr p
       val doIt = getF p
       val () =
           if Config.passShowPre (config, name) then
             doLayout (config, "Before Pass " ^ name ^ " IR",
                       (#printer inIr) (arg, config))
           else ()
       val () =
           if Config.passStatPre (config, name) then
             doLayout (config, "Before Pass " ^ name ^ " IR Stats",
                       (#stater inIr) (arg, config))
           else ()
       val ll = if PassData.getLevel pd > 0 then 1 else 0
       val () = Chat.log (config, ll, bold ("Starting Pass " ^ name))
       val t1 = Time.now ()
       val output = doIt (pd, basename, arg)
       val t2 = Time.now ()
       val ts = Time.toString (Time.- (t2, t1))
       val msg = "Finished Pass " ^ name ^ " (" ^ ts ^"s)"
       val () = Chat.log (config, ll, bold msg)
       val () =
           if Config.passShowPost (config, name) then
             doLayout (config, "After Pass " ^ name ^ " IR",
                       (#printer outIr) (output, config))
           else ()
       val () =
           if Config.passStatPost (config, name) then
             doLayout (config, "After Pass " ^ name ^ " IR Stats",
                       (#stater outIr) (output, config))
           else ()
     in output
     end

  fun skipPass (pd, name, skipIt, arg) = 
      let
        val () = Chat.log0 (PassData.getConfig pd,
                            bold ("Skipping Pass " ^ name))
        val res = skipIt (name, arg)
      in res
      end

  fun newPass (d, a, f, opt, skip) =
      let
        val p = P {description = d, associates = a, optional = opt, f = f}
        fun f (pd, basename, arg) =
            if Config.passEnabled (PassData.getConfig pd, #name d) then
              doPass p (pd, basename, arg)
            else
              skipPass (pd, #name d, skip, arg)
        val p = P {description = d, associates = a, optional = opt, f = f}
      in p
      end

  fun bad (n, _) =
      Fail.fail ("Pass", "bad", "Pass " ^ n ^ " cannot be disabled")

  fun skip (_, a) = a

  fun mkCompulsoryPass (d, a, f) =
      newPass (d, a, (fn (pd, _, a) => f (a, pd)), false, bad)

  fun mkOptPass (d, a, f) =
      newPass (d, a, (fn (pd, _, a) => f (a, pd)), true, skip)

  fun mkOptFullPass (d, a, f) =
      newPass (d, a, (fn (pd, b, a) => f (a, pd, b)), true, skip)

  fun mkFilePass (d, a, f) =
      newPass (d, a, (fn (pd, b, a) => f (a, pd, b)), false, bad)

  fun check (ps1, ps2) =
     let
       fun doOne (p, pns) = StringSet.insert (pns, getName p)
       val pns2 = List.fold (ps2, StringSet.empty, doOne)
       fun doOne p = isOptional p orelse StringSet.member (pns2, getName p)
       val allCompuls = List.forall (ps1, doOne)
       fun loop (ps, pns) =
           case ps
            of [] => true
             | p::ps =>
               let
                 val after = getMustBeAfter p
                 fun checkOne p = not (StringSet.member (pns, getName p))
               in
                 if List.forall (after, checkOne) then
                   loop (ps, StringSet.insert (pns, getName p))
                 else
                   false
               end
       val depsOk = loop (List.rev ps2, StringSet.empty)
     in allCompuls andalso depsOk
     end

  fun doPassPart (config, part, f) =
      let
        val () = Chat.log2 (config, "Starting part " ^ part)
        val t1 = Time.now ()
        val output = f ()
        val t2 = Time.now ()
        val ts = Time.toString (Time.- (t2, t1))
        val msg = "Finished part " ^ part ^ " (" ^ ts ^"s)"
        val () = Chat.log2 (config, msg)
      in output
      end

  exception Done

  fun doPass p = T (getF p)
  fun doPassWrap (p, f, g) =
      let
        fun h (pd, bn, x) =
            let
              val y = f x
              val z = getF p (pd, bn, y)
              val w = g z
            in w
            end
      in T h
      end
  fun doSubPass p = T (getF p o (fn (pd, bn, x) => (PassData.push pd, bn, x)))

  fun stopAt sp =
      let
        fun f (pd, _, arg) =
            if Config.stopLt (sp, Config.stop (PassData.getConfig pd)) then
              arg
            else
              raise Done
      in T f
      end

  fun >> (T f1, T f2) =
      let
        fun f (pd, base, arg) = f2 (pd, base, f1 (pd, base, arg))
      in T f
      end

  fun apply (T f1) = f1

  fun run (config, logger, cmd, args) = 
      let
        val () = logger (config, String.concatWith (cmd::args, " "))
        val doit = fn () => Process.exec(cmd, args)
        fun silently doit = 
         fn () => 
            Out.ignore(Out.standard, 
                       (fn () => 
                           Out.ignore(Out.error, doit)))
        val () = if Config.silent config then
                   Process.run (silently doit)
                 else
                   Process.run doit
      in ()
      end

end;
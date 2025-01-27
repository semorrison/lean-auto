import Lean
import Auto.Lib.ExprExtra
import Auto.Lib.MessageData
import Auto.Lib.MetaExtra
import Auto.Lib.MonadUtils
import Auto.Translation.Reduction
open Lean

initialize
  registerTraceClass `auto.collectInd

namespace Auto

/--
  Test whether a given inductive type is explicitly and inductive family.
  i.e., return `false` iff `numParams` match the number of arguments of
    the type constructor 
-/
def isFamily (tyctorname : Name) : CoreM Bool := do
  let .some (.inductInfo val) := (← getEnv).find? tyctorname
    | throwError "isFamily :: {tyctorname} is not a type constructor"
  return (Expr.forallBinders val.type).size != val.numParams

/--
  Test whether a given inductive type is an inductively defined proposition
-/
def isIndProp (tyctorname : Name) : CoreM Bool := do
  let .some (.inductInfo val) := (← getEnv).find? tyctorname
    | throwError "isIndProp :: {tyctorname} is not a type constructor"
  (Meta.withTransparency (n := MetaM) .all <|
    Meta.forallTelescopeReducing val.type fun _ body =>
      Meta.isDefEq body (.sort .zero)).run' {}

/--
  Whether the constructor is monomorphic after all parameters are instantiated.
-/
def isSimpleCtor (ctorname : Name) : CoreM Bool := do
  let .some (.ctorInfo val) := (← getEnv).find? ctorname
    | throwError "isSimpleCtor :: {ctorname} is not a type constructor"
  Meta.MetaM.run' <| Meta.forallBoundedTelescope val.type val.numParams fun _ body =>
    pure ((Expr.depArgs body).size == 0)

/--
  Returns true iff the inductive type is not explicitly an inductive family,
    and all constructors of this inductive type are simple (refer to `isSimpleCtor`)
-/
def isSimpleInductive (tyctorname : Name) : CoreM Bool := do
  let .some (.inductInfo val) := (← getEnv).find? tyctorname
    | throwError "isSimple :: {tyctorname} is not a type constructor"
  return (← val.ctors.allM isSimpleCtor) && !(← isFamily tyctorname)

structure SimpleIndVal where
  /-- Name of type constructor -/
  name : Name
  /-- Instantiated type constructor -/
  type : Expr
  /-- Array of `(instantiated_ctor, type_of_instantiated_constructor)` -/
  ctors : Array (Expr × Expr)

instance : ToMessageData SimpleIndVal where
  toMessageData siv :=
    m!"SimpleIndVal ⦗⦗ {siv.type} " ++ MessageData.array siv.ctors (fun (e₁, e₂) => m!"{e₁} : {e₂}") ++ m!" ⦘⦘"

def SimpleIndVal.zetaReduce (si : SimpleIndVal) : MetaM SimpleIndVal := do
  let ⟨name, type, ctors⟩ := si
  let ctors ← ctors.mapM (fun (val, ty) => do return (← Meta.zetaReduce val, ← Meta.zetaReduce ty))
  return ⟨name, ← Meta.zetaReduce type, ctors⟩

/--
  For a given type constructor `tyctor`, `CollectIndState[tyctor]`
    is an array of `(instantiated_tyctor, [SimpleIndVal associated to tyctor])`
-/
structure CollectInduct.State where
  recorded : HashMap Name (Array Expr)     := {}
  sis      : Array (Array SimpleIndVal) := #[]

abbrev IndCollectM := StateRefT CollectInduct.State MetaM

#genMonadState IndCollectM

private def collectSimpleInduct
  (tyctor : Name) (lvls : List Level) (args : Array Expr) : MetaM SimpleIndVal := do
  let .some (.inductInfo val) := (← getEnv).find? tyctor
    | throwError "collectSimpleInduct :: Unexpected error"
  let ctors ← (Array.mk val.ctors).mapM (fun ctorname => do
    let instctor := mkAppN (Expr.const ctorname lvls) args
    let type ← Meta.inferType instctor
    let type ← prepReduceExpr type
    return (instctor, type))
  return ⟨tyctor, mkAppN (Expr.const tyctor lvls) args, ctors⟩

mutual

  private partial def collectAppInstSimpleInduct (e : Expr) : IndCollectM Unit := do
    let .const tyctor lvls := e.getAppFn
      | return
    let .some (.inductInfo val) := (← getEnv).find? tyctor
      | return
    if !(← @id (CoreM _) (val.all.allM isSimpleInductive)) then
      trace[auto.collectInd] ("Warning : {tyctor} or some type within the " ++
        "same mutual block is not a simple inductive type. Ignoring it ...")
      return
    /-
      Do not translate typeclasses as inductive types
      Mathlib has a complex typeclass hierarchy, so translating typeclasses might make a mess
    -/
    if Lean.isClass (← getEnv) tyctor then
      return
    let args := e.getAppArgs
    if args.size != val.numParams then
      trace[auto.collectInd] "Warning : Parameters of {tyctor} in {e} is not fully instantiated. Ignoring it ..."
      return
    if !(← getRecorded).contains tyctor then
      setRecorded ((← getRecorded).insert tyctor #[])
    let .some arr := (← getRecorded).find? tyctor
      | throwError "collectAppInstSimpleInduct :: Unexpected error"
    for e' in arr do
      if ← Meta.isDefEq e e' then
        return
    for tyctor' in val.all do
      setRecorded ((← getRecorded).insert tyctor' (arr.push (mkAppN (.const tyctor' lvls) args)))
    let mutualInductVal ← val.all.mapM (collectSimpleInduct · lvls args)
    for inductval in mutualInductVal do
      for (_, type) in inductval.ctors do
        collectExprSimpleInduct type
    setSis ((← getSis).push ⟨mutualInductVal⟩)

  partial def collectExprSimpleInduct : Expr → IndCollectM Unit
  | e@(.app ..) => do
    collectAppInstSimpleInduct e
    let _ ← e.getAppArgs.mapM collectExprSimpleInduct
  | e@(.lam ..) => do trace[auto.collectInd] "Warning : Ignoring lambda expression {e}"
  | e@(.forallE _ ty body _) => do
    if body.hasLooseBVar 0 then
      trace[auto.collectInd] "Warning : Ignoring forall expression {e}"
      return
    collectExprSimpleInduct ty
    collectExprSimpleInduct body
  | .letE .. => throwError "collectExprSimpleInduct :: Let-expressions should have been reduced"
  | .mdata .. => throwError "collectExprSimpleInduct :: mdata should have been consumed"
  | .proj .. => throwError "collectExprSimpleInduct :: Projections should have been turned into ordinary expressions"
  | e => collectAppInstSimpleInduct e

end

def collectExprsSimpleInduct (es : Array Expr) : MetaM (Array (Array SimpleIndVal)) := do
  let (_, st) ← (es.mapM collectExprSimpleInduct).run {}
  return st.sis

end Auto

section Test

  private def skd (e : Expr) : Elab.Term.TermElabM Unit := do
    let (_, st) ← (Auto.collectExprSimpleInduct (Auto.Expr.eraseMData e)).run {}
    for siw in st.sis do
      for si in siw do
        IO.println <| ← MessageData.format m!"{si}"

  #check Meta.isClass?
  #getExprAndApply[List.cons 2|skd]
  #getExprAndApply[(Array Bool × Array Nat)|skd]

  mutual
    
    private inductive tree where
      | leaf : Nat → tree
      | node : treelist → tree

    private inductive treelist where
      | nil : treelist
      | cons : tree → treelist → treelist

  end

  #getExprAndApply[tree|skd]

  mutual
  
    private inductive Tree (α : Type u) where
      | leaf : α → Tree α
      | node : TreeList α → Tree α

    private inductive TreeList (α : Type u) where
      | nil : TreeList α
      | cons : Tree α → TreeList α → TreeList α

  end

  #getExprAndApply[Tree Int|skd]

end Test
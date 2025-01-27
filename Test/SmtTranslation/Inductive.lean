import Auto.Tactic

set_option auto.smt true
set_option trace.auto.smt.printCommands true
set_option trace.auto.smt.result true
set_option auto.proofReconstruction false

section Enum

  example (x y : Unit) : x = y ∧ x = () := by auto

  example (x y : Empty) : x = y := by auto

  example (_ : ¬ (∀ x y : Empty, False)) : False := by auto

  private inductive Color where
    | red
    | green
    | ultraviolet

  example (x y z t : Color) : x = y ∨ x = z ∨ x = t ∨ y = z ∨ y = t ∨ z = t := by auto

end Enum

section NonRecursive

  example (x y : α) (_ : Option.some x = Option.some y) : x = y := by auto

  -- **TODO**:
  -- Requires higher-order to first-order translation
  set_option trace.auto.printLemmas true in
  example (x : Option α) : Option.orElse x (fun _ => Option.none) = x := by auto

  -- **TODO**:
  -- · Recognize projections for structures
  -- · Better control over input??
  set_option trace.auto.lamReif.printResult true
  example (x : α × β) : x = (Prod.fst x, Prod.snd x) := by
    have h₁ : ∀ (x : α) (y : β) (z : α × β), z = (x, y) → Prod.fst z = x := fun _ _ _ h => by cases h; rfl
    have h₁ : ∀ (x : α) (y : β) (z : α × β), z = (x, y) → Prod.snd z = y := fun _ _ _ h => by cases h; rfl
    auto

end NonRecursive

section Recursive

  -- SMT solver is now able to recognize inductive types
  set_option auto.lamReif.prep.def false
  set_option trace.auto.lamReif.printResult true
  example (x y : α) : [x] ++ [y] = [x, y] := by
    -- Invoke definition unfolding
    -- **TODO**: Apply unfolding to λ inductive infos
    have h : ∀ (x y : List α), x ++ y = x.append y := fun _ _ => rfl
    auto [h] d[List.append]

  -- SMT solver times out on the following problem:
  -- set_option auto.redMode "all" in
  -- example (x y z : List Nat) : (x ++ y) ++ z = x ++ (y ++ z) := by
  --   auto d[List.append]

  mutual

    private inductive tree where
      | leaf : Nat → tree
      | node : treelist → tree

    private inductive treelist where
      | nil : treelist
      | cons : tree → treelist → treelist

  end

  set_option trace.auto.lamReif.printResult true
  example (x : tree) : (∃ (y : treelist), x = .node y) ∨ (∃ y, x = .leaf y) := by
    auto

end Recursive

section Mixed

  example (x y : α) : List.get? [x, y] 1 = .some y := by
    auto d[List.get?]

  example (x : α) : List.head? [x] = .some x := by
    have h₁ : List.head? (α := α) [] = .none := rfl
    have h₂ : ∀ (x : α) (ys : _), List.head? (x :: ys) = .some x := fun _ _ => rfl
    auto

  example (x : α) (y : List α) : List.head? (x :: y) = .some x := by
    have h₁ : List.head? (α := α) [] = .none := rfl
    have h₂ : ∀ (x : α) (ys : _), List.head? (x :: ys) = .some x := fun _ _ => rfl
    auto

  -- **TODO**: Did not get desired definitional equation
  example (x : α) : List.head? [x] = .some x := by
    auto d[List.head?]

end Mixed

/- Issues to be solved:
  1. Unable to deal with inductive families, like `Vector`
  2. Fails if constructor is dependent/polymorphic after monomorphization,
     for example `Fin`
-/
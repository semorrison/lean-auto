import Lake
open Lake DSL

package «auto» {
  -- add any package configuration options here
}

require mathlib from git
  "https://github.com/leanprover-community/mathlib4.git"

require Duper from git
  "https://github.com/leanprover-community/duper.git"

@[default_target]
lean_lib «Auto» {
  -- add any library configuration options here
}

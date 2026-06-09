# workbranch — terminal demo
#
# Render:  vhs docs/demo/demo.tape        ->  outputs docs/figs/workbranch-demo.gif
# Needs:   vhs (https://github.com/charmbracelet/vhs), git, and `workbranch` on PATH.
#          To record against the in-repo build:  export PATH="$PWD/bin:$PATH"
#
# The hidden setup block builds a throwaway project with two fake remotes, so the
# demo runs end-to-end without touching any real repository.

Output docs/figs/workbranch-demo.gif

Require workbranch
Require git

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 760
Set Padding 24
Set Theme "Dracula"
Set TypingSpeed 55ms

# --- hidden: build a throwaway multi-repo project and cd into it ---
Hide
Type 'cd "$(bash docs/demo/setup.sh)"'
Enter
Type "clear"
Enter
Show

# 1) Clone every base repo declared in .workbranch.config
Type "workbranch init"
Enter
Sleep 3s

# 2) One task workspace spanning every repo (Enter accepts each default task branch)
Type "workbranch add feat-login"
Enter
Sleep 1s
Enter
Sleep 800ms
Enter
Sleep 2.5s

# 3) Every repo lives under one task folder
Type "ls feat-login"
Enter
Sleep 2.5s

# 4) Base/task diff and dirty state across all repos at once
Type "workbranch status"
Enter
Sleep 3s

# 5) Pull + update every repo in the task to the latest base — one command
Type "workbranch refresh feat-login"
Enter
Sleep 3.5s

# ship it with `workbranch push feat-login` or `workbranch land` — see the README
Sleep 2.5s

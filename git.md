## 📘 Git Ultimate Cheatsheet (with Graphs & Explanations)

---

### 🔧 Configuration

```bash
git config user.name "Your Name"
git config user.email "you@example.com"
git config init.defaultBranch=main
```

> **Sets your identity and default branch name**. This is stored in your Git config file.

---

### 🏗️ Initialize a Repository

```bash
git init
```

> **Creates a new Git repository** in your current directory by adding a hidden `.git` folder.

---

### 📝 Track and Stage Files

```bash
git status
```

> Shows the current working status — tracked, untracked, and staged changes.

```bash
git add .
git add <file>
```

> Stages changes for commit. Use `.` for all files or specify files individually.

```bash
git diff
```

> Shows **unstaged changes** in your working directory.

```bash
git diff --cached
```

> Shows **staged changes** (ready to commit).

---

### ♻️ Restore / Unstage / Remove Files

```bash
git restore --staged <file>
```

> Removes the file from **staging** but keeps your changes.

```bash
git rm --cached <file>
```

> Unstages and removes the file **from Git** (but keeps it locally).

```bash
git rm <file>
```

> Deletes the file from both **Git** and your **filesystem**.

---

### 🔁 Renaming or Moving Files

```bash
git mv old.txt new.txt
```

> Git-native way to rename or move files.

---

### ✅ Committing

```bash
git commit -m "Message"
```

> Commits staged changes with a message.

```bash
git commit -am "Quick commit"
```

> Adds **only tracked files** and commits them (skip `git add`).

---

### 🕵️‍♂️ View Logs & Details

```bash
git log
git log --oneline
git log --graph --decorate
```

> See your project's history. Combine flags for a **visual history** with branch names:

```
* 1a2b3c4 (HEAD -> main, feature)
| * d4e5f6 (bugfix)
|/
* a1b2c3 Initial commit
```

```bash
git show <commit>
```

> Shows full details of a specific commit.

```bash
cat .git/HEAD
```

> Tells you which branch or commit your HEAD is pointing to.

---

### 🌿 Branching

```bash
git branch <branch>
```

> Creates a new branch.

```bash
git checkout <branch>
```

> Switches to another branch.

```bash
git checkout -b <branch>
```

> Creates and switches to a new branch in one go.

```bash
git branch
```

> Lists all local branches.

```bash
git branch -d <branch>
```

> Deletes a branch **only if it’s merged**.

---

### 🍒 Cherry Pick

```bash
git cherry-pick <commit>
```

> Applies a specific commit from one branch to another.

📈 Example:

```bash
git checkout main
git cherry-pick a1b2c3
```

```bash
# Before cherry-pick
feature: A---B---C
               \
main:     X---Y

# After cherry-pick C
main:     X---Y---C'
```

---

### 🔀 Merging

```bash
git merge <branch>
```

> Merges another branch into your current one.

```bash
git merge --abort
```

> Abort a merge if it gets messy.

---

### 🚀 Rebase

```bash
git rebase <branch>
```

> Moves your branch to start at the tip of another branch.

```bash
git rebase -i HEAD~3
```

> Interactive rebase: squash, reorder, fixup, or edit commits.

✅ **Squash commits** example:

```
pick a1 Commit A
squash b2 Commit B
squash c3 Commit C
```

---

### 🏷️ Tags

```bash
git tag
```

> Lists all tags.

```bash
git tag v1.0
```

> Create a lightweight tag.

```bash
git tag -a v1.0 -m "Release v1.0"
```

> Annotated tag with message (recommended for releases).

```bash
git show v1.0
```

> Shows details about a tag.

```bash
git push origin v1.0
```

> Push a tag to remote.

```bash
git push origin --tags
```

> Push **all** tags.

---

### 🔥 Undoing Commits

```bash
git reset --soft HEAD~1
```

> Undo last commit, but keep files **staged**.

```bash
git reset --mixed HEAD~1
```

> Undo last commit, files are **unstaged**.

```bash
git reset --hard HEAD~1
```

> Completely undo the last commit and discard all changes.

---

### 🔎 Git Ignore

#### 📄 `.gitignore`

```
*.log
node_modules/
.env
```

> Tells Git to **ignore** files or folders — great for logs, builds, secrets, etc.

---

### ⚙️ Git Attributes

#### 📄 `.gitattributes`

```gitattributes
*.sh text eol=lf
*.jpg binary
```



## 🎯 Bonus: Summary Table

| Command                    | Purpose                  |
| -------------------------- | ------------------------ |
| `git init`                 | Start new Git repo       |
| `git add`                  | Stage changes            |
| `git commit`               | Commit staged changes    |
| `git status`               | Check status             |
| `git log`                  | View commit history      |
| `git branch`               | Work with branches       |
| `git merge` / `git rebase` | Combine branches         |
| `git cherry-pick`          | Apply specific commits   |
| `git tag`                  | Mark versions            |
| `git reset` / `revert`     | Undo changes             |
| `.gitignore`               | Ignore certain files     |
| `.gitattributes`           | File behavior & settings |

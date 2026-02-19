# Quick dotfiles sync
dotfiles() {
    git -C "$HOME/dotfiles" add -A &&
    git -C "$HOME/dotfiles" commit -m "${1:-update dotfiles}" &&
    git -C "$HOME/dotfiles" push
}

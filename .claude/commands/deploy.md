bolero.local にデプロイしてください。以下の手順で実行：

1. 未コミットの変更があればコミットする
2. GitHub に push する
3. bolero.local で git pull する: `ssh toyoshi@bolero.local "cd ~/reweight && git pull"`
4. Gemfile に変更があれば bundle install する: `ssh toyoshi@bolero.local 'export PATH="$HOME/.rbenv/bin:$PATH" && eval "$($HOME/.rbenv/bin/rbenv init -)" && cd ~/reweight && bundle install'`
5. デプロイ結果を報告する

build() {
  echo "iniciando o build"

  export NODE_OPTIONS="--openssl-legacy-provider"

  npm install --prefix bia/client

  npm run build --prefix bia/client --no-preflight-check

  echo "build concluído"
}

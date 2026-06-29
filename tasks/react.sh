function build() {
  API_URL=$1
  cd bia
  npm install
  echo "iniciando o build..."
  NODE_OPTIONS="--openssl-legacy-provider RE

  npm install --prefix bia/client

  npm run build --prefix bia/client --no-preflight-check

  echo "build concluído"
}
echo "iniciando o processo de deploy"
. envio.sh
. build.sh
echo "Fazendo Deploy..."
build
envio_s3
echo "Deploy concluído"
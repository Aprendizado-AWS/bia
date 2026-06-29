function envio_s3() {
  echo "iniciando o envio para o S3"
  echo "Iniciando envio..."
  aws s3 sync ./bia/client/build/ s3://desafios-fundamentais-bia-teste  --profile aprendizadoaws    
  echo "Envio concluído"
}
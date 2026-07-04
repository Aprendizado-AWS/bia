#!/bin/bash
set -e

# =============================================================================
# deploy-versioned.sh
# Deploy da BIA com versionamento por commit hash no ECR.
# - Gera tag com o hash do commit atual (ex: abc1234)
# - Faz push apenas da tag versionada no ECR (sem :latest)
# - Registra nova revisão da task definition apontando para a imagem versionada
# - Atualiza o service ECS com a nova revisão
# =============================================================================

# --- Configurações ---
AWS_REGION="us-east-1"
ECR_REGISTRY="246288393057.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPO="$ECR_REGISTRY/bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_DEF_FAMILY="task-def-bia"

# IP público da EC2 onde a aplicação vai rodar (ajuste antes de executar)
VITE_API_URL="${VITE_API_URL:-http://SEU_IP_PUBLICO}"

# --- Commit hash ---
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
IMAGE_TAG="$COMMIT_HASH"

echo ""
echo "=============================================="
echo " BIA - Deploy Versionado"
echo "=============================================="
echo " Commit : $COMMIT_HASH"
echo " Imagem : $ECR_REPO:$IMAGE_TAG"
echo " Cluster: $CLUSTER"
echo " Service: $SERVICE"
echo "=============================================="
echo ""

# --- 1. Login no ECR ---
echo "[1/5] Login no ECR..."
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ECR_REGISTRY

# --- 2. Build da imagem ---
echo "[2/5] Build da imagem Docker..."
docker build \
  --build-arg VITE_API_URL=$VITE_API_URL \
  -t bia:$IMAGE_TAG \
  -f $(git rev-parse --show-toplevel)/Dockerfile \
  $(git rev-parse --show-toplevel)

# --- 3. Tag e push: apenas tag versionada ---
echo "[3/5] Tag e push para o ECR ($IMAGE_TAG)..."
docker tag bia:$IMAGE_TAG $ECR_REPO:$IMAGE_TAG

docker push $ECR_REPO:$IMAGE_TAG

# --- 4. Registrar nova revisão da task definition ---
echo "[4/5] Registrando nova revisão da task definition..."

# Busca a task def atual como base e substitui apenas a imagem
CURRENT_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition $TASK_DEF_FAMILY \
  --region $AWS_REGION \
  --query 'taskDefinition' \
  --output json)

# Monta o JSON da nova task def com a imagem versionada
NEW_TASK_DEF=$(echo $CURRENT_TASK_DEF | python3 -c "
import json, sys
td = json.load(sys.stdin)

# Atualiza a imagem do container bia
for c in td['containerDefinitions']:
    if c['name'] == 'bia':
        c['image'] = '$ECR_REPO:$IMAGE_TAG'

# Remove campos que a API de registro não aceita
for field in ['taskDefinitionArn', 'revision', 'status', 'requiresAttributes',
              'compatibilities', 'registeredAt', 'registeredBy', 'deregisteredAt']:
    td.pop(field, None)

print(json.dumps(td))
")

NEW_REVISION=$(aws ecs register-task-definition \
  --region $AWS_REGION \
  --cli-input-json "$NEW_TASK_DEF" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "    Nova revisão: $NEW_REVISION"

# --- 5. Atualizar o service com a nova revisão ---
echo "[5/5] Atualizando o service ECS..."
aws ecs update-service \
  --region $AWS_REGION \
  --cluster $CLUSTER \
  --service $SERVICE \
  --task-definition $NEW_REVISION \
  --output json > /dev/null

echo ""
echo "=============================================="
echo " Deploy concluído com sucesso!"
echo " Imagem  : $ECR_REPO:$IMAGE_TAG"
echo " Task Def: $NEW_REVISION"
echo "=============================================="
echo ""
echo " Acompanhe o deploy:"
echo " aws ecs describe-services --cluster $CLUSTER --services $SERVICE \\"
echo "   --query 'services[0].{status:status,running:runningCount,desired:desiredCount,taskDef:taskDefinition}'"
echo ""

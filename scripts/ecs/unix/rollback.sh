#!/bin/bash
set -e

# =============================================================================
# rollback.sh
# Rollback do service ECS para uma revisão específica da task definition.
# Uso: ./rollback.sh <numero_da_revisao>
# Exemplo: ./rollback.sh 4
# =============================================================================

# --- Configurações ---
AWS_REGION="us-east-1"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_DEF_FAMILY="task-def-bia"

# --- Validação do argumento ---
if [ -z "$1" ]; then
  echo ""
  echo "Uso: $0 <numero_da_revisao>"
  echo "Exemplo: $0 4"
  echo ""
  echo "Revisões disponíveis:"
  aws ecs list-task-definitions \
    --region $AWS_REGION \
    --family-prefix $TASK_DEF_FAMILY \
    --status ACTIVE \
    --sort DESC \
    --query 'taskDefinitionArns[*]' \
    --output table
  echo ""
  exit 1
fi

REVISION=$1
TASK_DEF="$TASK_DEF_FAMILY:$REVISION"

# --- Verifica se a revisão existe ---
echo ""
echo "=============================================="
echo " BIA - Rollback"
echo "=============================================="
echo " Cluster : $CLUSTER"
echo " Service : $SERVICE"
echo " Task Def: $TASK_DEF"
echo "=============================================="
echo ""

echo "Verificando se a revisão $TASK_DEF existe..."
IMAGE=$(aws ecs describe-task-definition \
  --task-definition $TASK_DEF \
  --region $AWS_REGION \
  --query 'taskDefinition.containerDefinitions[0].image' \
  --output text 2>/dev/null) || {
    echo "ERRO: Revisão '$TASK_DEF' não encontrada."
    exit 1
  }

echo "Imagem da revisão: $IMAGE"
echo ""

# --- Atualiza o service ---
echo "Atualizando o service para $TASK_DEF..."
aws ecs update-service \
  --region $AWS_REGION \
  --cluster $CLUSTER \
  --service $SERVICE \
  --task-definition $TASK_DEF \
  --output json > /dev/null

echo ""
echo "=============================================="
echo " Rollback iniciado com sucesso!"
echo " Task Def: $TASK_DEF"
echo " Imagem  : $IMAGE"
echo "=============================================="
echo ""
echo " Acompanhe o rollback:"
echo " aws ecs describe-services --cluster $CLUSTER --services $SERVICE \\"
echo "   --query 'services[0].{status:status,running:runningCount,desired:desiredCount,taskDef:taskDefinition}'"
echo ""

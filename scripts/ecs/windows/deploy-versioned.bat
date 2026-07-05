@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM deploy-versioned.bat
REM Deploy da BIA com versionamento por commit hash no ECR.
REM - Gera tag com o hash do commit atual (ex: abc1234)
REM - Faz push apenas da tag versionada no ECR (sem :latest)
REM - Registra nova revisao da task definition apontando para a imagem versionada
REM - Atualiza o service ECS com a nova revisao
REM =============================================================================

REM --- Configuracoes ---
set AWS_REGION=us-east-1
set ECR_REGISTRY=246288393057.dkr.ecr.us-east-1.amazonaws.com
set ECR_REPO=%ECR_REGISTRY%/bia
set CLUSTER=cluster-bia
set SERVICE=service-bia
set TASK_DEF_FAMILY=task-def-bia

REM IP publico da EC2 onde a aplicacao vai rodar (ajuste antes de executar)
if "%VITE_API_URL%"=="" set VITE_API_URL=http://SEU_IP_PUBLICO

REM --- Commit hash ---
for /f "tokens=*" %%i in ('git rev-parse --short HEAD 2^>nul') do set COMMIT_HASH=%%i
if "%COMMIT_HASH%"=="" set COMMIT_HASH=no-git
set IMAGE_TAG=%COMMIT_HASH%

echo.
echo ==============================================
echo  BIA - Deploy Versionado
echo ==============================================
echo  Commit : %COMMIT_HASH%
echo  Imagem : %ECR_REPO%:%IMAGE_TAG%
echo  Cluster: %CLUSTER%
echo  Service: %SERVICE%
echo ==============================================
echo.

REM --- 1. Login no ECR ---
echo [1/5] Login no ECR...
aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %ECR_REGISTRY%
if %errorlevel% neq 0 (echo ERRO: Falha no login do ECR & exit /b 1)

REM --- 2. Build da imagem ---
echo [2/5] Build da imagem Docker...
for /f "tokens=*" %%i in ('git rev-parse --show-toplevel') do set REPO_ROOT=%%i
docker build --build-arg VITE_API_URL=%VITE_API_URL% -t bia:%IMAGE_TAG% -f %REPO_ROOT%\Dockerfile %REPO_ROOT%
if %errorlevel% neq 0 (echo ERRO: Falha no build da imagem & exit /b 1)

REM --- 3. Tag e push: apenas tag versionada ---
echo [3/5] Tag e push para o ECR (%IMAGE_TAG%)...
docker tag bia:%IMAGE_TAG% %ECR_REPO%:%IMAGE_TAG%
docker push %ECR_REPO%:%IMAGE_TAG%
if %errorlevel% neq 0 (echo ERRO: Falha no push da imagem & exit /b 1)

REM --- 4. Registrar nova revisao da task definition ---
echo [4/5] Registrando nova revisao da task definition...

REM Busca a task def atual como base
aws ecs describe-task-definition --task-definition %TASK_DEF_FAMILY% --region %AWS_REGION% --query taskDefinition --output json > %TEMP%\current-task-def.json
if %errorlevel% neq 0 (echo ERRO: Falha ao buscar task definition & exit /b 1)

REM Monta o JSON da nova task def com a imagem versionada
python -c "
import json, sys
with open(r'%TEMP%\current-task-def.json') as f:
    td = json.load(f)

for c in td['containerDefinitions']:
    if c['name'] == 'bia':
        c['image'] = '%ECR_REPO%:%IMAGE_TAG%'

for field in ['taskDefinitionArn', 'revision', 'status', 'requiresAttributes',
              'compatibilities', 'registeredAt', 'registeredBy', 'deregisteredAt']:
    td.pop(field, None)

with open(r'%TEMP%\new-task-def.json', 'w') as f:
    json.dump(td, f)
"
if %errorlevel% neq 0 (echo ERRO: Falha ao gerar nova task definition & exit /b 1)

for /f "tokens=*" %%i in ('aws ecs register-task-definition --region %AWS_REGION% --cli-input-json file://%TEMP%\new-task-def.json --query taskDefinition.taskDefinitionArn --output text') do set NEW_REVISION=%%i
if %errorlevel% neq 0 (echo ERRO: Falha ao registrar task definition & exit /b 1)
echo     Nova revisao: %NEW_REVISION%

REM --- 5. Atualizar o service com a nova revisao ---
echo [5/5] Atualizando o service ECS...
aws ecs update-service --region %AWS_REGION% --cluster %CLUSTER% --service %SERVICE% --task-definition %NEW_REVISION% --output json > nul
if %errorlevel% neq 0 (echo ERRO: Falha ao atualizar o service & exit /b 1)

echo.
echo ==============================================
echo  Deploy concluido com sucesso!
echo  Imagem  : %ECR_REPO%:%IMAGE_TAG%
echo  Task Def: %NEW_REVISION%
echo ==============================================
echo.
echo  Acompanhe o deploy:
echo  aws ecs describe-services --cluster %CLUSTER% --services %SERVICE% ^
echo    --query "services[0].{status:status,running:runningCount,desired:desiredCount,taskDef:taskDefinition}"
echo.

endlocal

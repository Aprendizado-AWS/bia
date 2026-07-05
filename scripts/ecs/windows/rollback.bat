@echo off
setlocal

REM =============================================================================
REM rollback.bat
REM Rollback do service ECS para uma revisão específica da task definition.
REM Uso: rollback.bat <numero_da_revisao>
REM Exemplo: rollback.bat 4
REM =============================================================================

REM --- Configuracoes ---
set AWS_REGION=us-east-1
set CLUSTER=cluster-bia
set SERVICE=service-bia
set TASK_DEF_FAMILY=task-def-bia

REM --- Validacao do argumento ---
if "%1"=="" (
  echo.
  echo Uso: %0 ^<numero_da_revisao^>
  echo Exemplo: %0 4
  echo.
  echo Revisoes disponiveis:
  aws ecs list-task-definitions --region %AWS_REGION% --family-prefix %TASK_DEF_FAMILY% --status ACTIVE --sort DESC --query taskDefinitionArns[*] --output table
  echo.
  exit /b 1
)

set REVISION=%1
set TASK_DEF=%TASK_DEF_FAMILY%:%REVISION%

echo.
echo ==============================================
echo  BIA - Rollback
echo ==============================================
echo  Cluster : %CLUSTER%
echo  Service : %SERVICE%
echo  Task Def: %TASK_DEF%
echo ==============================================
echo.

REM --- Verifica se a revisao existe e pega a imagem ---
echo Verificando se a revisao %TASK_DEF% existe...
for /f "tokens=*" %%i in ('aws ecs describe-task-definition --task-definition %TASK_DEF% --region %AWS_REGION% --query taskDefinition.containerDefinitions[0].image --output text 2^>nul') do set IMAGE=%%i

if "%IMAGE%"=="" (
  echo ERRO: Revisao '%TASK_DEF%' nao encontrada.
  exit /b 1
)

echo Imagem da revisao: %IMAGE%
echo.

REM --- Atualiza o service ---
echo Atualizando o service para %TASK_DEF%...
aws ecs update-service --region %AWS_REGION% --cluster %CLUSTER% --service %SERVICE% --task-definition %TASK_DEF% --output json > nul
if %errorlevel% neq 0 (echo ERRO: Falha ao atualizar o service & exit /b 1)

echo.
echo ==============================================
echo  Rollback iniciado com sucesso!
echo  Task Def: %TASK_DEF%
echo  Imagem  : %IMAGE%
echo ==============================================
echo.
echo  Acompanhe o rollback:
echo  aws ecs describe-services --cluster %CLUSTER% --services %SERVICE% ^
echo    --query "services[0].{status:status,running:runningCount,desired:desiredCount,taskDef:taskDefinition}"
echo.

endlocal

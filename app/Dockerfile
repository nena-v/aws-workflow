FROM public.ecr.aws/lambda/python:3.12
# la base image contient déjà le client de l'interface d'exécution Lambda
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION
COPY app.py ${LAMBDA_TASK_ROOT}
CMD ["app.handlre"]
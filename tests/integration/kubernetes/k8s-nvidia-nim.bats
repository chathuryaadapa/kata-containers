#!/usr/bin/env bats
#
# Copyright (c) 2025 NVIDIA Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../common.bash"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

export POD_NAME_INSTRUCT="nvidia-nim-llama-3-1-8b-instruct"
export POD_SECRET_INSTRUCT="ngc-secret-instruct"

export DOCKER_CONFIG_JSON=$(
                echo -n "{\"auths\":{\"nvcr.io\":{\"username\":\"\$oauthtoken\",\"password\":\"${NGC_API_KEY}\",\"auth\":\"$(echo -n "\$oauthtoken:${NGC_API_KEY}" | base64 -w0)\"}}}" \
                | base64 -w0
        )

setup_file() {
	dpkg -s python3-pip 2>&1 >/dev/null || sudo apt -y install python3-pip
        dpkg -s python3-venv 2>&1 >/dev/null || sudo apt -y install python3-venv
        dpkg -s jq 2>&1 >/dev/null || sudo apt -y install jq

        python3 -m venv ${HOME}/.cicd/venv

        get_pod_config_dir

        pod_instruct_yaml_in="${pod_config_dir}/${POD_NAME_INSTRUCT}.yaml.in"
        pod_instruct_yaml="${pod_config_dir}/${POD_NAME_INSTRUCT}.yaml"

        envsubst < "${pod_instruct_yaml_in}" > "${pod_instruct_yaml}"

        export POD_INSTRUCT_YAML="${pod_instruct_yaml}"
}

@test "NVIDIA NIM Llama 3.1-8b Instruct" {
        kubectl apply -f "${POD_INSTRUCT_YAML}"
        kubectl wait --for=condition=Ready --timeout=500s pod "${POD_NAME_INSTRUCT}"
        export POD_IP_INSTRUCT=$(kubectl get pod "${POD_NAME_INSTRUCT}" -o jsonpath='{.status.podIP}')

        [ -n "${POD_IP_INSTRUCT}" ]
}

@test "List of models available for inference" {
        export MODEL_NAME=$(curl -sX GET "http://${POD_IP_INSTRUCT}:8000/v1/models" | jq '.data[0].id' | tr -d '"')
        echo "# MODEL_NAME=${MODEL_NAME}" >&3

        [ -n "${MODEL_NAME}" ]
}

@test "Simple OpenAI completion request" {
        QUESTION="What are Kata Containers?"
        ANWSER=$(curl -sX 'POST' \
                "http://${POD_IP_INSTRUCT}:8000/v1/completions" \
                -H "accept: application/json" \
                -H "Content-Type: application/json" \
                -d "{\"model\": \"${MODEL_NAME}\", \"prompt\": \"${QUESTION}\", \"max_tokens\": 64}" | jq '.choices[0].text')
        echo "# QUESTION: ${QUESTION}" >&3
        echo "# ANWSER: ${ANWSER}" >&3

        [ -n "${ANWSER}" ]
}

teardown_file() {
        kubectl delete -f "${POD_INSTRUCT_YAML}"
}

#!/usr/bin/env bash

clean() {
    local a=${1//[^[:alnum:]]/}
    echo "${a,,}"
}

clean Kr@nthi@30%&*()
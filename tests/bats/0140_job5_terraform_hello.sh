#!/usr/bin/env bats

# NOTE: the json content MUST be created using:
#   tar zcvf ../content_terraform.tar.gz . --owner=2001 --group=2001
#   base64 -w 0 ../content_terraform.tar.gz
# terraform will need write access (UID 2001 is gostint user injected into the
# container)

@test "Submitting job5 terraform hello world should return json" {
  # Get a default token for the api post authentication
  TOKEN=$(vault write -f auth/token/create policies=default -format=json | jq .auth.client_token -r)
  echo "$TOKEN"
  echo "$TOKEN" > $BATS_TMPDIR/token

  # Get secretId for the approle
  WRAPSECRETID=$(vault write -wrap-ttl=144h -f auth/approle/role/gostint-role/secret-id -format=json | jq .wrap_info.token -r)
  echo "WRAPSECRETID: $WRAPSECRETID" >&2

  # cat ../job5_terraform.json | jq ".wrap_secret_id=\"$WRAPSECRETID\"" > $BATS_TMPDIR/job.json

  QNAME=$(cat ../job5_terraform.json | jq .qname -r)

  # encrypt job payload using vault transit secret engine
  B64=$(base64 < ../job5_terraform.json)
  E=$(vault write transit/encrypt/gostint plaintext="$B64" -format=json | jq .data.ciphertext -r)
  echo "E: $E"

  # Put encrypted payload in a cubbyhole of an ephemeral token
  CUBBYTOKEN=$(vault token create -policy=default -ttl=60m -use-limit=2 -format=json | jq .auth.client_token -r)
  echo "CUBBYTOKEN: $CUBBYTOKEN" >&2

  VAULT_TOKEN=$CUBBYTOKEN vault write cubbyhole/job payload="$E" >&2 || exit 1

  # Create new job request with encrypted payload
  jq --arg qname "$QNAME" \
     --arg cubby_token "$CUBBYTOKEN" \
     --arg cubby_path "cubbyhole/job" \
     --arg wrap_secret_id "$WRAPSECRETID" \
     '. | .qname=$qname | .cubby_token=$cubby_token | .cubby_path=$cubby_path | .wrap_secret_id=$wrap_secret_id' \
     <<<'{}' >$BATS_TMPDIR/job.json
  cat $BATS_TMPDIR/job.json >&2

  J="$(curl -k -s https://127.0.0.1:3232/v1/api/job --header "X-Auth-Token: $TOKEN" -X POST -d @$BATS_TMPDIR/job.json | tee $BATS_TMPDIR/job5.json)"
  [ "$J" != "" ]
}

@test "job5 should be queued in the play job5 queue" {

  J="$(cat $BATS_TMPDIR/job5.json)"

  id=$(echo $J | jq ._id -r)
  status=$(echo $J | jq .status -r)
  qname=$(echo $J | jq .qname -r)

  [ "$id" != "" ] && [ "$status" == "queued" ] && [ "$qname" == "play job5" ]
}

@test "Be able to retrieve the current status" {
  TOKEN="$(cat $BATS_TMPDIR/token)"
  echo "TOKEN: $TOKEN" >&2
  J="$(cat $BATS_TMPDIR/job5.json)"

  ID=$(echo $J | jq ._id -r)

  R="$(curl -k -s https://127.0.0.1:3232/v1/api/job/$ID --header "X-Auth-Token: $TOKEN")"
  echo "R:$R" >&2
  status=$(echo $R | jq .status -r)

  [ "$status" == "queued" -o "$status" == "running" ]
}

@test "Status should eventually be success" {
  TOKEN="$(cat $BATS_TMPDIR/token)"
  echo "TOKEN: $TOKEN" >&2
  J="$(cat $BATS_TMPDIR/job5.json)"

  ID=$(echo $J | jq ._id -r)
  echo "ID:$ID" >&2

  status="queued"
  for i in {1..20}
  do
    sleep 1
    R="$(curl -k -s https://127.0.0.1:3232/v1/api/job/$ID --header "X-Auth-Token: $TOKEN")"
    echo "R:$R" >&2
    status=$(echo $R | jq .status -r)
    if [ "$status" != "queued" -a "$status" != "running" ]
    then
      break
    fi
  done
  echo "status after:$status" >&2
  echo "$R" > $BATS_TMPDIR/job5.final.json
  [ "$status" == "success" ]
}

@test "Should have final output in json" {
  R="$(cat $BATS_TMPDIR/job5.final.json)"

  echo "R:$R" >&2
  output="$(echo $R | jq .output -r)"

  echo "$output" | grep "greet = Hello World!"
}

set +x
set -e

num_workers=$CELERY_WORKERS
printf "Number of workers: $num_workers\n"

printf "########## Setting up environment ##########\n"
pushd $WORKSPACE

export DOCKER_DATA=$(pwd)/DOCKER_DATA/

printf "########## Copping records and config to workspace ##########\n"
cp -r ~/dumps ./inspire-next/.
cp ~/inspirehep.cfg .

pushd inspire-next

printf "########## Cleaning workspace ##########\n"
#docker-compose kill
#docker-compose rm -f || true
sudo rm -rf $DOCKER_DATA || true
docker rm -f $(docker ps -aq) || true
docker rmi $(docker images -q) || true
mkdir -p ${DOCKER_DATA}

printf "########## Pull and set up Docker ##########\n"
docker-compose pull
docker-compose -f docker-compose.deps.yml run --rm pip
docker-compose -f docker-compose.deps.yml run --rm assets

popd
sudo cp inspirehep.cfg ${DOCKER_DATA}/tmp/virtualenv/var/inspirehep-instance/
pushd inspire-next

printf "STARTING DAEMON... \n"
docker-compose up -d
sleep 5
echo "	[OK]"

printf "SCALING WORKERS... \n"
docker-compose scale worker=$num_workers
sleep 5
echo "	[OK]"

printf "########## Run Docker ##########\n"
docker-compose run --rm web inspirehep db create
docker-compose run --rm web inspirehep index init
docker-compose run --rm web inspirehep fixtures init

# Demo records first
#docker-compose run --rm web inspirehep migrator populate -f inspirehep/demosite/data/demo-records.xml.gz --wait=true
printf "########## Migrating records ##########\n"
CNT=0
for file in $(find dumps -type f); do
    echo "migrating: $file"
    let 'CNT+=1'
    if [ $((CNT % 50)) -eq 0 ]; then
      docker-compose restart indexer
    fi
    docker-compose run --rm web inspirehep migrator populate -f ${file} --wait=true || true
    echo "migrating: $file 	[OK]" 
	printf "\n"
done

printf "########## Count citations ##########\n"
docker-compose run --rm web inspirehep migrator count_citations

#printf "########## Cleaning Docker containers-workpspace ##########\n"
#sudo rm -rf $DOCKER_DATA || true
#docker rm -f $(docker ps -aq) || true
#docker rmi $(docker images -q) || true

popd
popd

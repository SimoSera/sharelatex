#!/bin/bash

#IDEA: controllo per versioni da 3.0.1 in su
#quello che fa è aggiornare in automatico con l'aggiunta 
#del backup del database mongo
#3.0.1-->3.5.13	full history migration
#3.5.13-->4.0.1	
#4.0.1-->4.*.*
#4.*.*-->5.0.1
#5.0.1-->5.1.1
#5.1.1-->5.???
#
#
#

# # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # #
# # #   Controlli generali    # # #
# # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # #


# Controllo numero dei parametri = 1
case $# in
1)	;;
*)
	echo Numero di parametri invalido
	echo Utilizzo:
	echo update.sh directory
	echo "directory: directory del toolkit di overleaf, es: /home/<user>/overleaf o overleaf/"
	exit 1
	;;	
esac

# Assegnamenti
D=$1
TEX=0


# Controllo $D directory traversabile
if test ! -d $D -o ! -x $D; then
	echo Errore: $D non e\' una directory o non è traversabile
	exit 2
fi
# Spostamento nella directory $D in quanto devo lavorare principalmente al suo interno
cd $D
if [[ ! $? == 0 ]]; then   # Controllo teoricamente non necessario avendo già controllato che sia traversabile
	echo "Errore inaspettato, impossibile spostarsi all'interno della directory $D nonostante sia traversabile"
	exit 3
fi


# preso da bin/upgrade, è necessario siccome senza questo molte funzioni di utility non funzionano
TOOLKIT_ROOT="$(dirname "$(realpath "$D")")"
if [[ ! -d "$TOOLKIT_ROOT/bin" ]] || [[ ! -d "$TOOLKIT_ROOT/config" ]]; then
  echo "ERROR: could not find root of overleaf-toolkit project (inferred project root as '$TOOLKIT_ROOT')"
  exit 1
fi



echo "Attenzione questa procedura non è completamente automatica, richiede all'utente qualche input e alcune verifiche sulla coretta esecuzione"
echo "Attenzione la procedura di aggiornamento richiederà diverse ore (circa 2/3 ore)"
continuare="n"
read -r -p "Sei sicuro di voler continuare? (S/N)" continuare
if [[ ! "$continuare" =~ [Ss] ]]; then
    echo "Ok, procedura di aggiornamento annullata"
    exit 5
fi






# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # #    Inizializzazione file di utility     # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
#prende dell utilities da lib/shared-functions.sh e due funzioni da bin/upgrade (non si può importare tutto il file purtroppo)
echo "Inclusione di alcune funzioni utili"



function git_pull_available() {
  local branch="$1"
  local fetch_output
  fetch_output="$(git -C "$TOOLKIT_ROOT" fetch --dry-run origin "$branch" 2>&1)"
  local filtered_fetch_output
  filtered_fetch_output="$(echo "$fetch_output" | grep '\-> origin/'"$branch")"
  if [[ -z "$filtered_fetch_output" ]]; then
    return 1
  else
    return 0
  fi
}

function handle_git_update() {
  local current_branch
  current_branch="$(git -C "$TOOLKIT_ROOT" rev-parse --abbrev-ref HEAD)"
  local current_commit
  current_commit="$(git -C "$TOOLKIT_ROOT" rev-parse --short HEAD)"

  if [[ ! "$current_branch" == "master" ]]; then
    echo "Warning: current branch is not master, '$current_branch' instead"
  fi

  if ! git_pull_available "$current_branch"; then
    echo "No code update available for download"
  else
    git -C "$TOOLKIT_ROOT" fetch origin "$current_branch"
  fi

  if ! is_up_to_date_with_remote "$current_branch"; then
    git -C "$TOOLKIT_ROOT" pull origin "$current_branch"
 fi
}

function read_seed_image_version() {
  SEED_IMAGE_VERSION="$(head -n 1 "$TOOLKIT_ROOT/lib/config-seed/version")"
  if [[ ! "$SEED_IMAGE_VERSION" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+(-RC[0-9]*)?(-with-texlive-full)?$ ]]; then
    echo "ERROR: invalid config-seed/version '${SEED_IMAGE_VERSION}'"
    exit 1
  fi
  SEED_IMAGE_VERSION_MAJOR=${BASH_REMATCH[1]}
  SEED_IMAGE_VERSION_MINOR=${BASH_REMATCH[2]}
  SEED_IMAGE_VERSION_PATCH=${BASH_REMATCH[3]}
}

function read_configuration() {
  local name=$1
  grep -E "^$name=" "$TOOLKIT_ROOT/config/overleaf.rc" \
  | sed -r "s/^$name=([\"']?)(.+)\1\$/\2/"
}

function git_diff() {
  git -C "$TOOLKIT_ROOT" diff "$@"
}

function is_up_to_date_with_remote() {
  local branch="$1"
  git_diff --quiet HEAD "origin/$branch"
}


#ASSICURATI DI AVERE DOCKER COMPOSE V2  guarda https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
sudo bin/backup-config -m copy "../backups/old-config"
if test -f config/docker-compose.override.yml; then
	sed -i "/version: '2.2'/d" "config/docker-compose.override.yml" 
fi
sudo bin/stop
sudo bin/up mongo -d




# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # #    Aggiornamento di Overleaf Toolkit    # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
echo Inizio aggiornamento del toolkit...:
#utilizzo la funzione copiata da upgrade.sh
handle_git_update # funzione per aggiornare il toolkit

echo Toolkit aggiornato
#importo nuovamente il file di utility siccome potrebbe essersi aggiornato
source "lib/shared-functions.sh"



# se il file overleaf.rc è fatto nel modo vecchio in cui MONGO_IMAGE coneteneva sia il nome dell'immagine che la versione (es: MONGO_IMAGE=mongo:4.0)
# Sostituisci con MONGO_IMAGE=mongo   e   MONGO_VERSION=4.0

# cambiamento del modo in cui è salvato il nome e la versione dell'immagine di mongo, come richiesto dal toolkit



mongo_image=$(read_configuration "MONGO_IMAGE")
mongo_version=$(read_configuration "MONGO_VERSION")
if [ -z "${mongo_version}" ]; then  #controllo se MONGO_VERSION esiste
	#se non esiste
	if [ -z "${mongo_image}" ]; then #controllo se mongo_image esiste
		#se mongo image non esiste
		#aggiunta di mongo image e mongo version dopo mongo datapath
		sudo sed -i '/^MONGO_DATA_PATH=/a MONGO_IMAGE=mongo\nMONGO_VERSION=4.0' config/overleaf.rc
	else
		#regular expression per fare la sostituzione di MONGO_IMAGE=4.0 a MONGO_IMAGE=mongo e MONGO_VERSION=4.0
		sudo sed -i -E 's/^(MONGO_IMAGE=mongo):([0-9.]+)/\1\nMONGO_VERSION=\2/' config/overleaf.rc
	fi
fi
if [[ ! $? == 0 ]] ; then
	echo "Errore durante l'aggiunta di MONGO_VERSION e MONGO_IMAGE a overleaf.rc"
	exit 10
fi

# Aggiunta di REDIS_AOF_PERSISTENCE in caso non sia già presente nel file overlaef.rc

if ! grep -q "^REDIS_AOF_PERSISTENCE=" "config/overleaf.rc" ; then
  # Se non esiste, aggiungilo dopo REDIS_DATA_PATH
  sed -i '/^REDIS_DATA_PATH=data\/redis/a REDIS_AOF_PERSISTENCE=true' "config/overleaf.rc"
fi


#funzione presente in lib/shared-functions.sh che si occupa di rinominare alcune variabili

sudo bin/rename-rc-vars








# # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # #
# # #   Fase di backup    # # #
# # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # #
echo Inizio della fase di Backup....
# Controlla l'esistenza delle directory data/ config/ data/mongo data/redis data/sharelatex
echo Creazione della directory per i backup: ../backups
# Controllo se la directory ../ è traversabile
if test ! -d "../" -o ! -x "../"; then
	echo Errore: $i non e\' una directory o non è traversabile
	exit 6
fi

if test ! -d "../backups"; then
	sudo mkdir ../backups # Creazione della cartella backups 
	if [[ ! $? == 0 ]]; then
		echo "Errore durante la creazione della cartella ../backups"
		exit 7
	fi
fi

echo Creazione backup di mongo con mongodump
sudo bin/docker-compose exec -T mongo  mongodump --archive --gzip  > dump.gz  ### MODIFICATO
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'esecuzione di mongodump"
	exit 8
fi
echo Stop dei docker container
sudo bin/stop mongo
echo Creazione backup degli altri dati
sudo tar --create --file ../backups/backupData.tar config/ data/ dump.gz
if [[ ! $? == 0 ]]; then
	echo "Errore durante la crezione del backup (creazione \"tarball\" con comando tar)"
	exit 9
fi
echo Fine della procedura di backup



# # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # #
# # #    Aggiornamento di Overleaf    # # #
# # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # #

echo Inizio della procedura di aggiornamento di Overleaf:

read_seed_image_version # funzione che legge la latest version
read_image_version      # funzione che legge la versione corrente  (definita in lib/shared-functions.sh)

if [[ ! ($SEED_IMAGE_VERSION_MAJOR > $IMAGE_VERSION_MAJOR || $SEED_IMAGE_VERSION_MINOR > $IMAGE_VERSION_MINOR || $SEED_IMAGE_VERSION_PATCH > $IMAGE_VERSION_PATCH) ]]; then
    echo "Versione più recente già installata"
    exit 0
fi

if [[ $SEED_IMAGE_VERSION_MAJOR > 6 ]]; then
	echo "Errore aggiornamento a major version!!"
	echo "Questo script è stato creato quando l'ultima versione disponibile era la versione 5.2.1"
	echo "Per questo motivo non sarà possibile aggiornare con questo script siccome saranno necessarie procedure aggiuntive"
	exit 11

elif [[ $SEED_IMAGE_VERSION_MINOR > 1 ]]; then
	echo "Attenzione questo script è stato creato quando l'ultima versione era la versione 5.2.1"
	echo "L'ultima versione attuale è la versione $SEED_IMAGE_VERSION"
	echo "Controlla le release notes per verificare se sono richieste ulteriori procedure (ad esmepio aggiornamento di MongoBD)"
	continuare="n"
	read -r -p "Si desidera aggiornare comunque alla versione $SEED_IMAGE_VERSION? (S/N)" continuare
	if [[ ! "$continuare" =~ [Ss] ]]; then
		echo "Ok, procedura di aggiornamento annullata"
		exit 12
	fi
fi 

# estrazione della versione di mongo dal file  config/overleaf.rc
mongo_version=$(read_configuration "MONGO_VERSION")
regex='^([0-9]+)\.([0-9]+)'

if [[ $mongo_version =~ $regex ]]; then
	mongo_major_version="${BASH_REMATCH[1]}"
	mongo_minor_version="${BASH_REMATCH[2]}"
else
	echo "Errore durante l'estrazione della versione di MongoDB da congif/overleaf.rc"
	exit 13
fi

#eliminazione di vecchie versioni
if test -f config/docker-compose.override.yml; then
	echo "Rimozione del file config/docker-compse.yml (copia di backup: config/__old.docker-compose.override.yml)"
	sudo cp config/docker-compose.override.yml config/__old.docker-compose.override.yml
	sudo rm config/docker-compose.override.yml
fi


sudo bin/up -d

#funzione per aggiornamento di mongo
function update_mongo(){
	echo "Inizio aggiornamento di mongo a $1.$2"
	sudo bin/up mongo -d
	# Run multiple MongoDB commands inside the "mongo" container
	
	sudo bin/docker-compose exec -T mongo mongo --quiet <<-EOF
	db.adminCommand( { setFeatureCompatibilityVersion: "$mongo_major_version.$mongo_minor_version" } )
	exit 
	EOF

	if [[ ! $? == 0 ]]; then
		echo "Errore durante l'esecuzione di un comando dentro al container mongo"
		exit 13
	fi
	sudo bin/stop mongo
	sudo sed -i "s/^MONGO_VERSION=$mongo_major_version\.$mongo_minor_version/MONGO_VERSION=$1.$2/" config/overleaf.rc
	if [[ ! $? == 0 ]]; then
		echo "Errore durante l'aggiornamento di mongo"
		exit 14
	fi
	sudo bin/up mongo -d
	if [[ ! $? == 0 ]]; then
		echo "Errore durante il riavvio di mongo"
		exit 15		
	fi
	mongo_major_version=$1
	mongo_minor_version=$2
	sudo docker image remove $(sudo docker images mongo  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null

}





# # # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # #
# # #    Aggiornamento alla versione 3.5.13     # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $IMAGE_VERSION_MAJOR == 3 && ($IMAGE_VERSION_MINOR < 5 || $IMAGE_VERSION_PATCH < 13) ]]; then
	echo "Inizio dell'aggiornamento alla versione 3.5.13"
	
	
	# Aggiornamento di mongo da 4.0 a 4.2
	if [[ $mongo_major_version == '4' && $mongo_minor_version == '0' ]];then
		update_mongo 4 2 
	fi
	
	# Aggiornamento di mongo da 4.2 a 4.4
	if [[ $mongo_major_version == '4' && $mongo_minor_version == '2' ]];then
		update_mongo 4 4
	fi
	# Aggiornamento alla versione 3.5.13
	sudo bin/stop
	echo "Aggiornamento alla versione 3.5.13"
	sudo echo 3.5.13 | sudo tee config/version > /dev/null
	sudo bin/up -d	
	if [[ ! $? == 0 ]]; then
		echo "Errore, impossibile avviare i container dopo l'aggiornamento"
		exit 16		
	fi

	# Procedura di Full Project History Migration
	echo Esecuzione procedura di full history migration
	tentativi=0
	overleaf_up=$(sudo bin/docker-compose exec sharelatex /bin/bash -c "curl http://localhost:3000/status")
	while [[ (! $overleaf_up == *"alive"*) && $tentativi<5 ]]
	do
		sudo bin/up -d
		if [[ ! $? == 0 ]]; then
			echo "Errore: errore durante l'avvio dei container"
			exit 17		
		fi
		overleaf_up=$(sudo bin/docker-compose exec sharelatex /bin/bash -c "curl http://localhost:3000/status")
		tentativi=$tentativi+1
	done

	if [[ ! $overleaf_up == *"alive"* ]];then
		echo ERRORE: overleaf non riesce ad essere avviato
		exit 18
	fi
	sudo bin/docker-compose exec sharelatex /bin/bash -c "cd /overleaf/services/web; VERBOSE_LOGGING=true node scripts/history/migrate_history.js --force-clean --fix-invalid-characters --convert-large-docs-to-file"
	if [[ ! $? == 0 ]]; then
		echo "Errore durante la procedura di full project history migration"
		exit 19		
	fi 
	continuare='n'
	read -r -p "La procedura è finira con successo (tutti documenti sono stati trasferiti con successo) e si desidera constinuare? (S/N)" continuare	
	if [[ ! "$continuare" =~ [Ss] ]]; then
    	echo "Ok, procedura di aggiornamento annullata"
    	exit 20	
	fi
	sudo bin/docker-compose exec sharelatex /bin/bash -c "cd /overleaf/services/web; node scripts/history/clean_sl_history_data.js"
	if [[ ! $? == 0 ]]; then
		echo "Errore durante la pulizia dei dati inutili"
		exit 21
	fi
	sudo bin/stop
	sudo bin/up -d
	if [[ ! $? == 0 ]]; then
		echo "Errore durante l'avvio dei container"
		exit 22
	fi
	read_image_version
	echo "Rimozione vecchie immagini docker"
	sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
	echo "Aggiornamento alla versione 3.5.13 Terminato"
fi




# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # #    Aggiornamento alla versione 4.0.1    # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $IMAGE_VERSION_MAJOR == 3 && $IMAGE_VERSION_MINOR > 4 && $IMAGE_VERSION_PATCH > 0 ]]; then  #almeno alla version 3.5.10 (il regex dentro shared-functions cattura solo l'ultimo numero (0) al posto di 10)
	echo "Inizio dell'aggiornamento alla versione 4.0.1"
	
	echo "Aggiornamento di Redis"
	# Aggiunta del parametro REDIS_IMAGE a overleaf.rc (con versione 6.2 che è la versione necessaria per la 4.0.*)
	sudo sed -i '/^REDIS_AOF_PERSISTENCE=/a REDIS_IMAGE=redis:6.2' config/overleaf.rc
	if [[ ! $? == 0 ]]; then
		echo "ERRORE: impossibile cambiare la versione in config/verison per redis"
		exit 22
	fi
	echo "Aggiornamento alla versione 4.0.1"
	sudo bin/stop
	sudo echo 4.0.1 | sudo tee config/version >/dev/null
	if [[ ! $? == 0 ]]; then
		echo "ERRORE: impossibile cambiare la versione in config/verison"
		exit 22
	fi
	sudo bin/up -d	
	if [[ ! $? == 0 ]]; then
		echo "Errore durante l'avvio dei container"
		exit 23
	fi

	echo "Rimozione vecchie immagini docker"
	sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
	sudo docker image remove $(sudo docker images redis  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
	read_image_version      # funzione che legge la versione corrente  (definita in lib/shared-functions.sh)

	echo "Aggiornamento alla versione 4.0.1 Terminato"
fi


# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # #    Aggiornamento alla versione 4.2.8    # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $IMAGE_VERSION_MAJOR < 5 && ($IMAGE_VERSION_MINOR < 2 || $IMAGE_VERSION_PATCH < 8) ]]; then #se la versione è minore della 4.2.8
	echo "Inizio dell'aggiornamento alla versione 4.2.8"
	sudo bin/stop
	
	# Aggiornamento di mongo da 4.4 a 5.0
	if [[ $mongo_major_version == '4' && $mongo_minor_version == '4' ]];then
		update_mongo 5 0
	fi
	sudo  bin/up -d
	echo "Aggiornamento alla versione 4.2.8"
	sudo bin/stop
	sudo echo 4.2.8 | sudo tee config/version > /dev/null
	if [[ ! $? == 0 ]]; then
		echo "Errore: impossibile cambiare la versione in config/version"
		exit 24
	fi
	sudo bin/up -d	
	if [[ ! $? == 0 ]]; then
		echo "Errore durante l'avvio dei container"
		exit 25
	fi
	echo "Pulizia di alcuni file inutili rimasti dalla Full Project History Migration"

	sudo bin/docker-compose exec sharelatex /bin/bash -c "cd /overleaf/services/web; node scripts/history/clean_sl_history_data.js"
	if [[ ! $? == 0 ]]; then
		echo "Errore durante la pulizia dei dati inutili della project history"
		exit 26
	fi	
	
	echo "Rimozione vecchie immagini docker"
	sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
	read_image_version      # funzione che legge la versione corrente  (definita in lib/shared-functions.sh)

	echo "Aggiornamento alla versione 4.2.8 Terminato"


fi
	

	
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # #    Aggiornamento alla versione 5.0.3    # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $IMAGE_VERSION_MAJOR == 4  && $MONGO_VERSION_MAJOR> 4  ]]; then #versione overleaf almeno 4.x e versione mongo almeno 5.0
	echo "Inizio dell'aggiornamento alla versione 5.0.3"
	
	echo "Aggiornamento alla versione 5.0.3"
	sudo bin/stop
	sudo echo 5.0.3 | sudo tee config/version > /dev/null
	if [[ ! $? == 0 ]]; then
		echo "Errore: impossibile cambiare la versione in config/version"
		exit 27
	fi

	#procedura richiesta, cambiare i nomi alle variabili per la versione 5.0
	echo Ora ti verra chiesto se vuoi rinominare delle variabili, dovrai confermare
	sudo bin/rename-env-vars-5-0
	if [[ ! $? == 0 ]]; then
		echo "Errore durante la procedura di rinomina delle variabili (bin/rename-env-vars-5-0)"
		exit 28
	fi
	# rimuovo la riga che inizia con TEXMFVAR=... da variables.env siccome non è più necessaria e deve essere cancellata
	sudo sed -i '/^TEXMFVAR=/d' config/variables.env 
	
	sudo bin/up -d	
	if [[ ! $? == 0 ]]; then
		echo "Errore durante l'avvio dei container"
		exit 30
	fi
	
	echo "Rimozione vecchie immagini docker"
	sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
	read_image_version      # funzione che legge la versione corrente  (definita in lib/shared-functions.sh)

	echo "Aggiornamento alla versione 5.0.3 Terminato"
fi

if [[ $IMAGE_VERSION_MAJOR == 5 ]]; then
	
	#aggiornamento di mongo alla versone 6.0
	if [[ $mongo_major_version == '5' ]];then
		update_mongo 6 0
	fi

	echo "Inizio dell'aggiornamento alla versione più recente attraverso il toolkit"
	echo Attenzione per fare questo aggiornamento verrà utilizzato il toolkit siccome aggiornerà in automatico alla versione più recente
	echo Confermare inserendo y quando richiesto
	sudo bin/stop
	sudo bin/upgrade --skip-git-update

	sudo bin/up -d	
	if [[ ! $? == 0 ]]; then
		echo "Errore durante l'avvio dei container"
		exit 31
	fi
	read_image_version      # funzione che legge la versione corrente  (definita in lib/shared-functions.sh)

	
	echo "Rimozione vecchie immagini docker"
	sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
	echo "Aggiornamento alla versione più recente Terminato"
	echo "# # # # # # # # # # # # #"
	echo Prima di installare TeXLive full
	echo Consiglio di vericare che Overleaf funzioni in questo stato
	echo Se molti documenti non compilano è normale siccome non sono installati tutti i pacchetti
	echo "Puoi verificare creando un file usando l'esempio di Overleaf"
	read -r -p "Overleaf funzione correttamente e desideri continuare con l'installazione di TeXLive Full (richiederà circa tra i 30 minuti e un ora)? (S/N)" continuare	
	if [[ ! "$continuare" =~ [Ss] ]]; then
    	echo "Ok, procedura di aggiornamento annullata"
    	exit 32
	fi
fi
sudo docker rmi sharelatex/sharelatex-full > /dev/null 2>/dev/null
echo "Inizio installazione TeXLive Full"
echo "Prima di iniziare ti chiedo di assicurarti di avere una connessione stabile e di avere abbastanza spazio nel disco"
echo "L'installazione richiederà almeno un paio di ore (durante le quali non deve essere interrotta)"
echo "Lo spazio richiesto dovrebbero essere circa 18GB (esegui in un altro terminale sudo docker exec sharelatex tlmgr info scheme-full e moltiplica lo spazio per due)"
read -r -p "Desideri iniziare con l'installazione? (S/N)" continuare	
if [[ ! "$continuare" =~ [Ss] ]]; then
	echo "Ok, procedura di installazione annullata"
	exit 33
fi

echo "Inizio installazione"
sudo docker exec sharelatex tlmgr install scheme-full
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'avvio dei container"
	exit 34
fi
echo "Installazione di TeXLive full terminata"
echo "Salvataggio dell'immagine docker...."
sudo docker commit sharelatex sharelatex/sharelatex:$IMAGE_VERSION_MAJOR.$IMAGE_VERSION_MINOR.$IMAGE_VERSION_PATCH-with-texlive-full
sudo bin/stop
sudo echo "-with-texlive-full" | sudo tee -a config/version > /dev/null
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'avvio dei container"
	exit 35
fi
sudo bin/up -d
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'avvio dei container"
	exit 36
fi
sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null

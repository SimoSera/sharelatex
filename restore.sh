#!/bin/bash



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
if [[ ! -d "$TOOLKIT_ROOT/bin" ]] || [[ ! -d "$TOOLKIT_ROOT/lib" ]]; then
  echo "ERROR: could not find root of overleaf-toolkit project (inferred project root as '$TOOLKIT_ROOT')"
  exit 1
fi




# rimuovo i vecchi file
sudo rm -rf config/
sudo rm -rf data/
sudo tar -xvf ../backups/backupData.tar
if test -f config/docker-compose.override.yml; then
	echo "Rimozione del file config/docker-compse.yml (copia di backup: config/__old.docker-compose.override.yml)"
	sudo cp config/docker-compose.override.yml config/__old.docker-compose.override.yml
	sudo rm config/docker-compose.override.yml
fi
sudo bin/up -d
sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null


read -r -p "desideri anche reinstallare texlive-full (senza molti documenti non compileranno)?" continuare
if [[ ! "$continuare" =~ [Ss] ]]; then
	echo "Ok, procedura di installazione annullata"
	exit 5
fi

echo "Inizio installazione"
sudo docker exec sharelatex tlmgr install scheme-full
#controlla ASSOLUTAMENTE
echo "Installazione di TeXLive full terminata"
echo "Salvataggio dell'immagine docker...."
sudo docker commit sharelatex sharelatex/sharelatex:$IMAGE_VERSION_MAJOR.$IMAGE_VERSION_MINOR.$IMAGE_VERSION_PATCH-with-texlive-full
sudo bin/stop
sudo echo "-with-texlive-full" | sudo tee -a config/version > /dev/null
#controlla ASSOLUTAMENTE
sudo bin/up -d
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'avvio dei container"
	exit 34
fi
sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null

#!/bin/bash



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





echo "Questa procedura non è completamente automatica"
echo "Attenzione la procedura di aggiornamento richiederà tra i 30 minuti e 1 ora, si desidera contianuare (S/N)"
continuare="n"
read -r -p "Sei sicuro di voler continuare? (S/N)" continuare
if [[ ! "$continuare" =~ [Ss] ]]; then
    echo "Ok, procedura di aggiornamento annullata"
    exit 4
fi




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
	exit 5
fi

if test ! -d "../backups"; then
	sudo mkdir ../backups # Creazione della cartella backups 
	if [[ ! $? == 0 ]]; then
		echo "Errore durante la creazione della cartella ../backups"
		exit 6
	fi
fi

echo Creazione backup di mongo con mongodump
sudo bin/docker-compose exec -T mongo  mongodump --archive --gzip  > dump.gz  ### MODIFICATO
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'esecuzione di mongodump"
	exit 7
fi
echo Stop dei docker container
sudo bin/stop mongo
echo Creazione backup degli altri dati
sudo tar -cvzf ../backups/backupData.tar ./
if [[ ! $? == 0 ]]; then
	echo "Errore durante la crezione del backup (creazione \"tarball\" con comando tar)"
	exit 8
fi
echo Fine della procedura di backup



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # #    Aggiornamento di Overleaf Toolkit e Overlaf    # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

echo Inizio della procedura di aggiornamento di Overleaf:
echo ""
echo "Avvio di bin/upgrade"
sudo bin/stop
sudo bin/upgrade
sudo bin/up -d	
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'avvio dei container"
	exit 9
fi


# # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # #
# # #    Installazione di TexLive Full    # # #
# # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # #



echo "# # # # # # # # # # # # #"
echo Prima di installare TeXLive :
echo Consiglio di vericare che Overleaf funzioni in questo stato
echo Se molti documenti non compilano è normale siccome non sono installati tutti i pacchetti
echo "Puoi verificare il funzionamento creando un file usando l'esempio di Overleaf"
read -r -p "Overleaf funzione correttamente e desideri continuare con l'installazione di TeXLive Full (richiederà circa tra i 30 minuti e un ora)? (S/N)" continuare	
if [[ ! "$continuare" =~ [Ss] ]]; then
	echo "Ok, procedura di aggiornamento annullata"
	exit 10
fi

echo "Inizio installazione TeXLive Full"
echo "Prima di iniziare assicurati di avere una connessione stabile e di avere abbastanza spazio nel disco"
echo "Lo spazio disponibile è:"
sudo df -h /
echo "Ecco alcuni dati sull'installazione, lo spazio necessarrio sarà il doppio di quello scritto qua sotto:"
echo $(sudo docker exec sharelatex tlmgr info scheme-full | grep "^sizes:" | awk '{print $2}')
read -r -p "Desideriri RIMUOVERE DEFINITIVAMENTE le vecchie immagini docker che non vengono più utilizzate per creare spazio? (S/N)" continuare	
if [[  "$continuare" =~ [Ss] ]]; then	
	echo Rimozione delle vecchie immagini inutilizzate per creare spazio
	sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
	sudo docker image remove $(sudo docker images mongo  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
	sudo docker image remove $(sudo docker images redis  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
	sudo docker rmi sharelatex/sharelatex-full > /dev/null 2>/dev/null
fi
echo "Ora lo spazio disponibile è:"
sudo df -h /
read -r -p "Desideri iniziare con l'installazione? (S/N)" continuare	
if [[ ! "$continuare" =~ [Ss] ]]; then
	echo "Ok, procedura di installazione annullata"
	exit 33
fi

echo "Inizio installazione"
sudo docker exec sharelatex tlmgr install scheme-full
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'installazione"
	exit 11
fi
echo "Installazione di TeXLive full terminata"
echo "Ora controlla che tutto funzioni su overleaf"
read -r -p "Funziona tutto correttamente e desideri salvare questa immagine? (S/N)" continuare	
if [[ !  "$continuare" =~ [Ss] ]]; then	
	echo "Ok procedura fermata"
	exit 12
fi
sudo docker commit sharelatex $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}" |head -n 1)-with-texlive-full

sudo bin/stop
sudo echo "-with-texlive-full" | sudo tee -a config/version > /dev/null
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'avvio dei container"
	exit 13
fi
sudo bin/up -d
if [[ ! $? == 0 ]]; then
	echo "Errore durante l'avvio dei container"
	exit 14
fi
read -r -p "Desideriri RIMUOVERE DEFINITIVAMENTE l'immagine docker vecchia per liberare spazio? (S/N)" continuare	
if [[  "$continuare" =~ [Ss] ]]; then	
	sudo docker image remove $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null
fi

echo "Procedura di aggiornamento Terminata"


sudo docker image list $(sudo docker images sharelatex/sharelatex  --format "{{.Repository}}:{{.Tag}}")  > /dev/null 2> /dev/null

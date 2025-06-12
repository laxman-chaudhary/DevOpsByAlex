mkdir -p ./logs ./data
sudo chown 999:999 ./logs ./data
sudo chmod 2770 ./logs ./data
docker compose up -d && echo && docker compose ps
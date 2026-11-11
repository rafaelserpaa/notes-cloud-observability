import logging, os, random, time
import requests

URL = os.environ["TARGET_URL"]
logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger("loadgen")

n = 0
while True:
    n += 1
    sorteio = random.random()
    try:
        if sorteio < 0.6:
            r = requests.get(URL + "/", timeout=5)
        elif sorteio < 0.95:
            r = requests.post(URL + "/notas", data={"texto": f"nota de teste {n}"}, timeout=5)
        else:
            r = requests.get(URL + "/rota-inexistente", timeout=5)
        log.info("requisicao n=%d metodo=%s status=%d ms=%d", n,
                 r.request.method, r.status_code, r.elapsed.total_seconds() * 1000)
    except requests.RequestException as e:
        log.error("falha na requisicao n=%d erro=%s", n, e)
    time.sleep(random.uniform(0.2, 1.5))

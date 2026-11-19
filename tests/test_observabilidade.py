"""Fitness functions de observabilidade (apostila da Aula 14, Seção 4).

Falham o build se um POST /notas deixar de gerar, no mesmo trace, o span da
requisição HTTP e o span do INSERT no banco, ou se o texto da nota vazar para a
telemetria. Rodam dentro do target `test` do Dockerfile, ou seja, contra o
app.py e as bibliotecas OpenTelemetry que vão para produção, com um PostgreSQL
descartável ao lado (buildspecs/observabilidade.yml).
"""
from opentelemetry import trace
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

exporter = InMemorySpanExporter()
provider = TracerProvider()
provider.add_span_processor(SimpleSpanProcessor(exporter))
trace.set_tracer_provider(provider)

Psycopg2Instrumentor().instrument(enable_commenter=False)
import app as notas  # noqa: E402

FlaskInstrumentor().instrument_app(notas.app)

TEXTO_SENSIVEL = "nota do pipeline 4111-1111-1111-1111"


def _post_nota():
    exporter.clear()
    resposta = notas.app.test_client().post("/notas", data={"texto": TEXTO_SENSIVEL})
    assert resposta.status_code in (302, 303), resposta.status_code
    return exporter.get_finished_spans()


def _spans_do_insert(spans):
    return [s for s in spans if s.name.upper().startswith("INSERT")]


def test_post_notas_gera_span_http_e_span_do_insert():
    spans = _post_nota()
    nomes = [s.name for s in spans]

    http = [s for s in spans if s.kind == trace.SpanKind.SERVER]
    assert http, f"nenhum span HTTP foi gerado: {nomes}"

    insert = _spans_do_insert(spans)
    assert insert, f"nenhum span do INSERT foi gerado: {nomes}"

    assert insert[0].context.trace_id == http[0].context.trace_id, \
        "o INSERT não está no mesmo trace da requisição"


def test_span_http_tem_a_rota():
    """As regras de SLI e o dashboard agrupam e filtram por http_route."""
    spans = _post_nota()
    http = [s for s in spans if s.kind == trace.SpanKind.SERVER]
    assert http, "nenhum span HTTP foi gerado"
    assert http[0].attributes.get("http.route") == "/notas", dict(http[0].attributes)


def test_texto_da_nota_nao_vaza_para_a_telemetria():
    """Telemetria também é dado (Aula 13): o INSERT leva o placeholder, nunca o texto."""
    spans = _post_nota()

    insert = _spans_do_insert(spans)
    assert insert, f"nenhum span do INSERT foi gerado: {[s.name for s in spans]}"
    statement = insert[0].attributes.get("db.statement") or insert[0].attributes.get("db.query.text")
    assert statement and "%s" in statement, f"db.statement sem placeholder: {statement!r}"

    for span in spans:
        for chave, valor in (span.attributes or {}).items():
            assert TEXTO_SENSIVEL not in str(valor), \
                f"o texto da nota vazou no atributo {chave!r} do span {span.name!r}"

from app import handler


def test_handler_repond_200():
    assert handler({}, {})["statusCode"] == 200


def test_handler_affiche_la_version():
    assert "version" in handler({}, {})["body"]
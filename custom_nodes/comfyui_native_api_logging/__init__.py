import json
import logging
import os

from server import PromptServer


ENABLED_VALUES = {"1", "true", "yes", "on"}


def log_api_request(json_data):
    """Log the native ComfyUI prompt graph without changing the request."""
    if os.getenv("COMFYUI_LOG_API_REQUESTS", "false").lower() not in ENABLED_VALUES:
        return json_data

    logging.info(
        "[ComfyUI API] request=%s",
        json.dumps(json_data, ensure_ascii=False, sort_keys=True, default=str),
    )
    return json_data


PromptServer.instance.add_on_prompt_handler(log_api_request)

NODE_CLASS_MAPPINGS = {}

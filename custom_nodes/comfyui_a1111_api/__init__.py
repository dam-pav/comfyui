import asyncio
import base64
import hashlib
import json
import logging
import os
import random
import re

from aiohttp import ClientSession, web
from server import PromptServer


routes = PromptServer.instance.routes

SAMPLERS = {
    "Euler": "euler",
    "Euler a": "euler_ancestral",
    "Heun": "heun",
    "DPM2": "dpm_2",
    "DPM2 a": "dpm_2_ancestral",
    "DPM++ 2S a": "dpmpp_2s_ancestral",
    "DPM++ 2M": "dpmpp_2m",
    "DPM++ SDE": "dpmpp_sde",
    "DPM++ 2M SDE": "dpmpp_2m_sde",
    "DPM++ 3M SDE": "dpmpp_3m_sde",
    "DPM fast": "dpm_fast",
    "DPM Fast": "dpm_fast",
    "DPM adaptive": "dpm_adaptive",
    "DPM Adaptive": "dpm_adaptive",
    "LMS": "lms",
    "DDIM": "ddim",
    "UniPC": "uni_pc",
    # Agnaistic currently contains this misspelling in its sampler list.
    "Huen": "heun",
}

SCHEDULERS = {
    "automatic": "normal",
    "normal": "normal",
    "karras": "karras",
    "exponential": "exponential",
    "sgm_uniform": "sgm_uniform",
    "simple": "simple",
    "ddim_uniform": "ddim_uniform",
    "beta": "beta",
}

_active_prompt_id = None
_selected_checkpoint = None
EXPLICIT_WEIGHT_PATTERN = re.compile(
    r"\([^():]+:-?(?:\d+(?:\.\d*)?|\.\d+)\)"
)


def _origin(request):
    # ComfyUI's internal port is fixed by the image command. Using loopback also
    # avoids sending internal requests back through a reverse proxy.
    return "http://127.0.0.1:8188"


async def _json(session, method, url, **kwargs):
    async with session.request(method, url, **kwargs) as response:
        body = await response.text()
        if response.status >= 400:
            raise web.HTTPBadGateway(
                text=json.dumps({"error": body}),
                content_type="application/json",
            )
        return json.loads(body)


async def _models(request):
    async with ClientSession() as session:
        info = await _json(
            session,
            "GET",
            f"{_origin(request)}/object_info/CheckpointLoaderSimple",
        )
    return info["CheckpointLoaderSimple"]["input"]["required"]["ckpt_name"][0]


def _model_record(name):
    return {
        "title": name,
        "model_name": name.rsplit(".", 1)[0],
        "hash": None,
        "sha256": None,
        "filename": name,
        "config": None,
    }


def _resolve_sampler(payload):
    label = str(
        os.getenv("A1111_API_SAMPLER")
        or payload.get("sampler_name")
        or payload.get("sampler_index")
        or "Euler"
    )
    scheduler_label = str(
        os.getenv("A1111_API_SCHEDULER") or payload.get("scheduler", "")
    ).lower()

    # A1111 historically encodes the scheduler in the sampler display name.
    for suffix, scheduler_name in (
        (" Karras", "karras"),
        (" Exponential", "exponential"),
    ):
        if label.endswith(suffix):
            label = label[: -len(suffix)]
            if not scheduler_label:
                scheduler_label = scheduler_name
            break

    sampler = SAMPLERS.get(label, label)
    scheduler = SCHEDULERS.get(scheduler_label or "normal", scheduler_label or "normal")
    return sampler, scheduler


async def _validate_sampler(request, sampler, scheduler):
    async with ClientSession() as session:
        info = await _json(
            session,
            "GET",
            f"{_origin(request)}/object_info/KSampler",
        )
    required = info["KSampler"]["input"]["required"]
    allowed_samplers = required["sampler_name"][0]
    allowed_schedulers = required["scheduler"][0]
    errors = []
    if sampler not in allowed_samplers:
        errors.append(
            {
                "parameter": "sampler_name",
                "value": sampler,
                "allowed": allowed_samplers,
            }
        )
    if scheduler not in allowed_schedulers:
        errors.append(
            {
                "parameter": "scheduler",
                "value": scheduler,
                "allowed": allowed_schedulers,
            }
        )
    if errors:
        logging.error("[A1111 API] invalid sampler settings: %s", errors)
        raise web.HTTPBadRequest(
            text=json.dumps(
                {
                    "error": "Invalid sampler configuration",
                    "details": errors,
                }
            ),
            content_type="application/json",
        )


@routes.get("/sdapi/v1/sd-models")
async def sd_models(request):
    return web.json_response([_model_record(name) for name in await _models(request)])


@routes.get("/sdapi/v1/samplers")
async def samplers(_request):
    return web.json_response(
        [{"name": name, "aliases": [], "options": {}} for name in SAMPLERS]
    )


@routes.get("/sdapi/v1/schedulers")
async def schedulers(_request):
    return web.json_response(
        [
            {"name": name, "label": name, "aliases": [], "default_rho": -1.0}
            for name in SCHEDULERS
        ]
    )


@routes.get("/sdapi/v1/options")
async def get_options(request):
    global _selected_checkpoint
    models = await _models(request)
    if _selected_checkpoint not in models:
        _selected_checkpoint = models[0] if models else ""
    return web.json_response({"sd_model_checkpoint": _selected_checkpoint})


@routes.post("/sdapi/v1/options")
async def set_options(request):
    global _selected_checkpoint
    payload = await request.json()
    requested_model = payload.get("sd_model_checkpoint")
    if requested_model:
        models = await _models(request)
        matches = [
            name
            for name in models
            if name == requested_model or requested_model in name
        ]
        if len(matches) != 1:
            raise web.HTTPBadRequest(
                text=json.dumps({"error": "No unique matching checkpoint is available"}),
                content_type="application/json",
            )
        _selected_checkpoint = matches[0]
    return web.json_response({})


@routes.get("/sdapi/v1/loras")
async def loras(_request):
    return web.json_response([])


@routes.get("/sdapi/v1/upscalers")
async def upscalers(_request):
    return web.json_response([])


@routes.get("/sdapi/v1/embeddings")
async def embeddings(_request):
    return web.json_response({"loaded": {}, "skipped": {}})


@routes.get("/sdapi/v1/cmd-flags")
async def cmd_flags(_request):
    return web.json_response({})


@routes.get("/sdapi/v1/progress")
async def progress(_request):
    return web.json_response(
        {
            "progress": 0.0,
            "eta_relative": 0.0,
            "state": {},
            "current_image": None,
            "textinfo": None,
        }
    )


@routes.post("/sdapi/v1/interrupt")
async def interrupt(request):
    async with ClientSession() as session:
        await _json(session, "POST", f"{_origin(request)}/interrupt", json={})
    return web.json_response({})


@routes.post("/sdapi/v1/txt2img")
async def txt2img(request):
    global _active_prompt_id, _selected_checkpoint

    payload = await request.json()
    if payload.get("alwayson_scripts"):
        raise web.HTTPNotImplemented(
            text=json.dumps({"error": "alwayson_scripts are not supported"}),
            content_type="application/json",
        )

    models = await _models(request)
    requested_model = (
        payload.get("override_settings", {}).get("sd_model_checkpoint")
        or payload.get("sd_model_checkpoint")
    )
    checkpoint = requested_model or (models[0] if models else None)
    if not requested_model and _selected_checkpoint in models:
        checkpoint = _selected_checkpoint
    if checkpoint not in models:
        matches = [name for name in models if checkpoint and checkpoint in name]
        checkpoint = matches[0] if len(matches) == 1 else None
    if not checkpoint:
        raise web.HTTPBadRequest(
            text=json.dumps({"error": "No matching checkpoint is available"}),
            content_type="application/json",
        )

    sampler_label = payload.get("sampler_name") or payload.get("sampler_index") or "Euler"
    sampler, scheduler = _resolve_sampler(payload)
    await _validate_sampler(request, sampler, scheduler)
    seed = int(payload.get("seed", -1))
    if seed < 0:
        seed = random.randrange(0, 2**63)
    clip_skip = int(payload.get("clip_skip", 1) or 1)
    clip_source = ["1", 1]
    prompt_mode = os.getenv("A1111_API_PROMPT_MODE", "comfy").lower()
    if prompt_mode not in {"comfy", "a1111"}:
        logging.warning(
            "[A1111 API] unsupported prompt mode %r; using 'comfy'",
            prompt_mode,
        )
        prompt_mode = "comfy"
    normalize_prompt_weights = (
        os.getenv("A1111_API_PROMPT_NORMALIZATION", "true").lower()
        in {"1", "true", "yes", "on"}
    )
    positive_node = "A1111Prompt" if prompt_mode == "a1111" else "CLIPTextEncode"
    negative_node = (
        "A1111PromptNegative" if prompt_mode == "a1111" else "CLIPTextEncode"
    )
    positive_inputs = {"text": payload.get("prompt", ""), "clip": clip_source}
    negative_inputs = {
        "text": payload.get("negative_prompt", ""),
        "clip": clip_source,
    }
    if prompt_mode == "a1111":
        positive_inputs["normalization"] = normalize_prompt_weights
        positive_inputs["debug"] = False
        negative_inputs["normalization"] = normalize_prompt_weights
        negative_inputs["debug"] = False

    workflow = {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": checkpoint},
        },
        "2": {
            "class_type": positive_node,
            "inputs": positive_inputs,
        },
        "3": {
            "class_type": negative_node,
            "inputs": negative_inputs,
        },
        "4": {
            "class_type": "EmptyLatentImage",
            "inputs": {
                "width": int(payload.get("width", 512)),
                "height": int(payload.get("height", 512)),
                "batch_size": (
                    int(payload.get("batch_size", 1))
                    * int(payload.get("n_iter", 1))
                ),
            },
        },
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["1", 0],
                "positive": ["2", 0],
                "negative": ["3", 0],
                "latent_image": ["4", 0],
                "seed": seed,
                "steps": int(payload.get("steps", 20)),
                "cfg": float(payload.get("cfg_scale", 7.0)),
                "sampler_name": sampler,
                "scheduler": scheduler,
                "denoise": 1.0,
            },
        },
        "6": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["5", 0], "vae": ["1", 2]},
        },
        "7": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "a1111_api", "images": ["6", 0]},
        },
    }
    if clip_skip > 1:
        workflow["8"] = {
            "class_type": "CLIPSetLastLayer",
            "inputs": {
                "clip": ["1", 1],
                "stop_at_clip_layer": -clip_skip,
            },
        }
        workflow["2"]["inputs"]["clip"] = ["8", 0]
        workflow["3"]["inputs"]["clip"] = ["8", 0]

    logging.info(
        "[A1111 API] txt2img checkpoint=%r prompt_chars=%d negative_chars=%d "
        "prompt_sha256=%s negative_sha256=%s "
        "size=%dx%d steps=%d cfg=%s seed=%d sampler=%s scheduler=%s clip_skip=%d "
        "batch=%d prompt_mode=%s positive_encoder=%s negative_encoder=%s "
        "normalization=%s positive_explicit_weights=%d negative_explicit_weights=%d",
        checkpoint,
        len(payload.get("prompt", "")),
        len(payload.get("negative_prompt", "")),
        hashlib.sha256(payload.get("prompt", "").encode()).hexdigest()[:16],
        hashlib.sha256(payload.get("negative_prompt", "").encode()).hexdigest()[:16],
        workflow["4"]["inputs"]["width"],
        workflow["4"]["inputs"]["height"],
        workflow["5"]["inputs"]["steps"],
        workflow["5"]["inputs"]["cfg"],
        seed,
        sampler,
        scheduler,
        clip_skip,
        workflow["4"]["inputs"]["batch_size"],
        prompt_mode,
        positive_node,
        negative_node,
        normalize_prompt_weights if prompt_mode == "a1111" else "n/a",
        len(EXPLICIT_WEIGHT_PATTERN.findall(payload.get("prompt", ""))),
        len(EXPLICIT_WEIGHT_PATTERN.findall(payload.get("negative_prompt", ""))),
    )

    async with ClientSession() as session:
        queued = await _json(
            session, "POST", f"{_origin(request)}/prompt", json={"prompt": workflow}
        )
        _active_prompt_id = queued["prompt_id"]
        history = None
        for _ in range(3600):
            result = await _json(
                session, "GET", f"{_origin(request)}/history/{_active_prompt_id}"
            )
            if _active_prompt_id in result:
                history = result[_active_prompt_id]
                break
            await asyncio.sleep(0.25)
        if history is None:
            raise web.HTTPGatewayTimeout(text="Generation did not finish in time")

        images = []
        for output in history.get("outputs", {}).values():
            for image in output.get("images", []):
                async with session.get(
                    f"{_origin(request)}/view",
                    params={
                        "filename": image["filename"],
                        "subfolder": image.get("subfolder", ""),
                        "type": image.get("type", "output"),
                    },
                ) as response:
                    response.raise_for_status()
                    images.append(base64.b64encode(await response.read()).decode())

    _active_prompt_id = None
    parameters = dict(payload)
    parameters["seed"] = seed
    return web.json_response(
        {
            "images": images,
            "parameters": parameters,
            "info": json.dumps(
                {
                    "seed": seed,
                    "all_seeds": [seed + index for index in range(len(images))],
                    "prompt": payload.get("prompt", ""),
                    "negative_prompt": payload.get("negative_prompt", ""),
                    "width": int(payload.get("width", 512)),
                    "height": int(payload.get("height", 512)),
                    "sampler_name": sampler_label,
                    "sd_model_name": checkpoint,
                }
            ),
        }
    )


NODE_CLASS_MAPPINGS = {}

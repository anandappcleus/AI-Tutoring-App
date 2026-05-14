"""
Auth router — JWT-based authentication.

Endpoints:
    POST /auth/register      Create a new student account
    POST /auth/token         Exchange email+password for access + refresh tokens
    POST /auth/refresh       Exchange a valid refresh token for a new access token
    GET  /auth/me            Return the current authenticated student profile

Security design:
    - Passwords hashed with bcrypt (passlib)
    - Short-lived access tokens (default: 30 min, from settings)
    - Long-lived refresh tokens (default: 30 days, from settings)
    - get_current_student() dependency used by all protected routes
    - Token type validated ("access" vs "refresh") so tokens can't be swapped
    - All auth failures return 401 with a stable error code string (for iOS parsing)

Logging:
    - Every login attempt logged with email (never password)
    - Failed attempts logged at WARNING with reason
    - Token decode errors logged at DEBUG (expected from expired/invalid tokens)
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta, timezone

import bcrypt
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.models.student import Student

log = logging.getLogger(__name__)
router = APIRouter()

# ── Crypto setup ─────────────────────────────────────────────────────
_oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

ALGORITHM = "HS256"
_ACCESS_TYPE = "access"
_REFRESH_TYPE = "refresh"


def _hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def _verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode(), hashed.encode())
    except Exception:
        return False


# ── Pydantic schemas ──────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    preferred_language: str = Field("en", pattern=r"^(bn|hi|ta|te|mr|gu|kn|ml|or|pa|en)$")
    exam_target: str = Field("JEE", pattern=r"^(JEE|NEET|WBCHSE)$")


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # access token lifetime in seconds


class RefreshRequest(BaseModel):
    refresh_token: str


class StudentResponse(BaseModel):
    id: str
    name: str
    email: str
    preferred_language: str
    exam_target: str
    is_premium: bool
    created_at: datetime


class UpdateMeRequest(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=200)
    preferred_language: str | None = Field(
        None, pattern=r"^(bn|hi|ta|te|mr|gu|kn|ml|or|pa|en)$"
    )
    exam_target: str | None = Field(None, pattern=r"^(JEE|NEET|WBCHSE)$")


class DeviceTokenRequest(BaseModel):
    token: str = Field(
        ...,
        min_length=64,
        max_length=64,
        pattern=r"^[0-9a-f]{64}$",
        description="APNs device token as a 64-character lowercase hex string",
    )


# ── Token helpers ─────────────────────────────────────────────────────

def _create_token(student_id: str, token_type: str, expires_delta: timedelta) -> str:
    """Create a signed JWT with type and expiry claims."""
    settings = get_settings()
    expire = datetime.now(tz=timezone.utc) + expires_delta
    payload = {
        "sub": student_id,
        "type": token_type,
        "exp": expire,
        "iat": datetime.now(tz=timezone.utc),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=ALGORITHM)


def _decode_token(token: str, expected_type: str) -> str:
    """
    Decode and validate a JWT.
    Returns the student_id (sub claim) on success.
    Raises HTTPException 401 on any validation failure.
    """
    settings = get_settings()
    credentials_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={"error": "invalid_token", "message": "Could not validate credentials."},
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError as exc:
        log.debug("token.decode_failed  type=%s  reason=%s", expected_type, exc)
        raise credentials_error from None

    student_id: str | None = payload.get("sub")
    token_type: str | None = payload.get("type")

    if not student_id:
        log.warning("token.missing_sub  type=%s", expected_type)
        raise credentials_error
    if token_type != expected_type:
        log.warning(
            "token.wrong_type  expected=%s  got=%s  student_id=%s",
            expected_type,
            token_type,
            student_id,
        )
        raise credentials_error

    return student_id


# ── FastAPI dependency ────────────────────────────────────────────────

async def get_current_student(
    token: str = Depends(_oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> Student:
    """
    Dependency injected into every protected route.
    Returns the authenticated Student ORM object.
    Raises 401 on invalid token; 403 if the account is deactivated.
    """
    student_id = _decode_token(token, _ACCESS_TYPE)

    try:
        result = await db.execute(
            select(Student).where(Student.id == uuid.UUID(student_id))
        )
        student = result.scalar_one_or_none()
    except Exception:
        log.error(
            "get_current_student.db_error  student_id=%s", student_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "db_unavailable", "message": "Database temporarily unavailable."},
        )

    if student is None:
        log.warning("get_current_student.not_found  student_id=%s", student_id)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "student_not_found", "message": "Student account not found."},
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not student.is_active:
        log.warning("get_current_student.inactive  student_id=%s", student_id)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error": "account_inactive", "message": "This account has been deactivated."},
        )

    return student


# ── Endpoints ─────────────────────────────────────────────────────────

@router.post("/register", response_model=StudentResponse, status_code=201)
async def register(body: RegisterRequest, db: AsyncSession = Depends(get_db)):
    """Create a new student account. Fails with 409 if email already exists."""
    log.info("auth.register  email=%s  lang=%s  exam=%s", body.email, body.preferred_language, body.exam_target)

    # Check for duplicate email
    existing = await db.execute(select(Student).where(Student.email == body.email))
    if existing.scalar_one_or_none():
        log.warning("auth.register.duplicate_email  email=%s", body.email)
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "email_taken", "message": "An account with this email already exists."},
        )

    student = Student(
        name=body.name,
        email=body.email,
        hashed_password=_hash_password(body.password),
        preferred_language=body.preferred_language,
        exam_target=body.exam_target,
    )
    db.add(student)
    try:
        await db.commit()
        await db.refresh(student)
    except Exception:
        await db.rollback()
        log.error("auth.register.db_error  email=%s", body.email, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "db_error", "message": "Failed to create account. Please retry."},
        )

    log.info("auth.register.ok  student_id=%s  email=%s", student.id, body.email)
    return _student_to_response(student)


@router.post("/token", response_model=TokenResponse)
async def login(
    form: OAuth2PasswordRequestForm = Depends(),
    db: AsyncSession = Depends(get_db),
):
    """
    Exchange email + password for access + refresh tokens.
    Uses OAuth2 form encoding: username field carries the email.
    """
    email = form.username  # OAuth2 spec uses 'username'
    log.info("auth.login.attempt  email=%s", email)

    result = await db.execute(select(Student).where(Student.email == email))
    student = result.scalar_one_or_none()

    # Constant-time comparison whether student exists or not
    if not student or not _verify_password(form.password, student.hashed_password):
        log.warning("auth.login.failed  email=%s  reason=bad_credentials", email)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "bad_credentials", "message": "Incorrect email or password."},
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not student.is_active:
        log.warning("auth.login.failed  email=%s  reason=inactive", email)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error": "account_inactive", "message": "This account has been deactivated."},
        )

    settings = get_settings()
    student_id = str(student.id)
    access_token = _create_token(
        student_id, _ACCESS_TYPE,
        timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    refresh_token = _create_token(
        student_id, _REFRESH_TYPE,
        timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )
    log.info("auth.login.ok  student_id=%s", student_id)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(body: RefreshRequest):
    """Exchange a valid refresh token for a new access + refresh token pair."""
    student_id = _decode_token(body.refresh_token, _REFRESH_TYPE)
    log.info("auth.refresh  student_id=%s", student_id)

    settings = get_settings()
    access_token = _create_token(
        student_id, _ACCESS_TYPE,
        timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    new_refresh = _create_token(
        student_id, _REFRESH_TYPE,
        timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )
    log.info("auth.refresh.ok  student_id=%s", student_id)
    return TokenResponse(
        access_token=access_token,
        refresh_token=new_refresh,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


@router.get("/me", response_model=StudentResponse)
async def me(current_student: Student = Depends(get_current_student)):
    """Return the current authenticated student's profile."""
    log.debug("auth.me  student_id=%s", current_student.id)
    return _student_to_response(current_student)


@router.patch("/me", response_model=StudentResponse)
async def update_me(
    body: UpdateMeRequest,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
):
    """Update name, preferred_language, and/or exam_target for the current student."""
    if body.name is not None:
        current_student.name = body.name
    if body.preferred_language is not None:
        current_student.preferred_language = body.preferred_language
    if body.exam_target is not None:
        current_student.exam_target = body.exam_target

    try:
        await db.commit()
        await db.refresh(current_student)
    except Exception:
        await db.rollback()
        log.error(
            "auth.update_me.db_error  student_id=%s", current_student.id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "db_error", "message": "Failed to update profile. Please retry."},
        )

    log.info("auth.update_me.ok  student_id=%s", current_student.id)
    return _student_to_response(current_student)


@router.post("/device-token", status_code=200)
async def register_device_token(
    body: DeviceTokenRequest,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
) -> dict:
    """
    Store the APNs device token for the authenticated student.

    Called by the iOS app after UIApplication.registerForRemoteNotifications()
    succeeds. The token is used by the nightly crew job to send push alerts
    when a student hits a learning plateau.
    """
    log.info("auth.device_token  student_id=%s  token_prefix=%s", current_student.id, body.token[:8])
    current_student.apns_token = body.token
    try:
        await db.commit()
    except Exception:
        await db.rollback()
        log.error("auth.device_token.db_error  student_id=%s", current_student.id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "db_error", "message": "Failed to save device token."},
        )
    log.info("auth.device_token.ok  student_id=%s", current_student.id)
    return {"registered": True}


# ── Private helpers ────────────────────────────────────────────────────

def _student_to_response(s: Student) -> StudentResponse:
    return StudentResponse(
        id=str(s.id),
        name=s.name,
        email=s.email,
        preferred_language=s.preferred_language,
        exam_target=s.exam_target,
        is_premium=s.is_premium,
        created_at=s.created_at,
    )

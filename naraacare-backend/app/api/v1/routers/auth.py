"""Auth endpoints (doc 04 section 2.1). Logic lives in ``app.domain.auth.service``."""

from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks, Depends, Request, Response, status

from app.api.v1.deps import AuthServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.domain.auth.service import OTP_COOLDOWN_S, OTP_TTL_S, TokenPair
from app.middleware.rate_limit import client_ip_or_none, rate_limit
from app.schemas.auth import (
    AppleSignInRequest,
    ChallengeResponse,
    ChangePasswordRequest,
    ForgotPasswordRequest,
    ForgotPasswordResponse,
    GoogleSignInRequest,
    LinkRequest,
    LoginRequest,
    OtpResendRequest,
    OtpVerifyRequest,
    RefreshRequest,
    ResendResponse,
    ResetPasswordRequest,
    SignupRequest,
    TokenPairResponse,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _pair(pair: TokenPair) -> TokenPairResponse:
    return TokenPairResponse(
        access_token=pair.access_token,
        access_expires_in_s=pair.access_expires_in_s,
        refresh_token=pair.refresh_token,
        refresh_expires_in_s=pair.refresh_expires_in_s,
        onboarding_required=pair.onboarding_required,
    )


@router.post(
    "/signup",
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("auth_signup_ip"))],
)
async def signup(
    body: SignupRequest, request: Request, background: BackgroundTasks, auth: AuthServiceDep
) -> ChallengeResponse:
    challenge_id = await auth.signup(
        email=body.email,
        password=body.password,
        confirm_password=body.confirm_password,
        policy_versions=body.policy_versions.model_dump(),
        installation_id=body.installation_id,
        ip=client_ip_or_none(request.scope),
        background=background,
    )
    return ChallengeResponse(
        challenge_id=challenge_id, expires_in_s=OTP_TTL_S, resend_after_s=OTP_COOLDOWN_S
    )


@router.post("/otp/verify", dependencies=[Depends(rate_limit("auth_otp_verify"))])
async def verify_otp(body: OtpVerifyRequest, auth: AuthServiceDep) -> TokenPairResponse:
    return _pair(
        await auth.verify_email(
            challenge_id=body.challenge_id, code=body.code, installation_id=body.installation_id
        )
    )


@router.post(
    "/otp/resend",
    status_code=status.HTTP_202_ACCEPTED,
    dependencies=[Depends(rate_limit("auth_otp_resend"))],
)
async def resend_otp(
    body: OtpResendRequest, background: BackgroundTasks, auth: AuthServiceDep
) -> ResendResponse:
    return ResendResponse(
        resend_after_s=await auth.resend(challenge_id=body.challenge_id, background=background)
    )


@router.post("/login", dependencies=[Depends(rate_limit("auth_login"))])
async def login(
    body: LoginRequest, request: Request, background: BackgroundTasks, auth: AuthServiceDep
) -> TokenPairResponse:
    return _pair(
        await auth.login(
            email=body.email,
            password=body.password,
            installation_id=body.installation_id,
            ip=client_ip_or_none(request.scope),
            background=background,
        )
    )


@router.post("/oauth/google", dependencies=[Depends(rate_limit("auth_oauth"))])
async def google_sign_in(
    body: GoogleSignInRequest, background: BackgroundTasks, auth: AuthServiceDep
) -> TokenPairResponse:
    return _pair(
        await auth.social_sign_in(
            provider="google",
            token=body.id_token,
            nonce=body.nonce,
            installation_id=body.installation_id,
            authorization_code=None,
            background=background,
        )
    )


@router.post("/oauth/apple", dependencies=[Depends(rate_limit("auth_oauth"))])
async def apple_sign_in(
    body: AppleSignInRequest, background: BackgroundTasks, auth: AuthServiceDep
) -> TokenPairResponse:
    return _pair(
        await auth.social_sign_in(
            provider="apple",
            token=body.identity_token,
            nonce=body.nonce,
            installation_id=body.installation_id,
            authorization_code=body.authorization_code,
            background=background,
        )
    )


@router.post("/oauth/link", dependencies=[Depends(rate_limit("auth_link"))])
async def link_identity(
    body: LinkRequest, request: Request, background: BackgroundTasks, auth: AuthServiceDep
) -> TokenPairResponse:
    return _pair(
        await auth.link(
            link_token=body.link_token,
            password=body.password,
            installation_id=body.installation_id,
            ip=client_ip_or_none(request.scope),
            background=background,
        )
    )


@router.post("/token/refresh", dependencies=[Depends(rate_limit("auth_refresh"))])
async def refresh(body: RefreshRequest, auth: AuthServiceDep) -> TokenPairResponse:
    return _pair(
        await auth.refresh(refresh_token=body.refresh_token, installation_id=body.installation_id)
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(principal: CurrentUser, auth: AuthServiceDep) -> Response:
    await auth.logout(principal)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
async def logout_all(principal: CurrentUser, auth: AuthServiceDep) -> Response:
    await auth.logout_all(principal)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/password/forgot",
    status_code=status.HTTP_202_ACCEPTED,
    dependencies=[Depends(rate_limit("auth_password_forgot"))],
)
async def forgot_password(
    body: ForgotPasswordRequest, background: BackgroundTasks, auth: AuthServiceDep
) -> ForgotPasswordResponse:
    return ForgotPasswordResponse(
        challenge_id=await auth.forgot_password(email=body.email, background=background)
    )


@router.post(
    "/password/reset",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(rate_limit("auth_password_reset"))],
)
async def reset_password(
    body: ResetPasswordRequest, background: BackgroundTasks, auth: AuthServiceDep
) -> Response:
    await auth.reset_password(
        challenge_id=body.challenge_id,
        code=body.code,
        new_password=body.new_password,
        confirm_password=body.confirm_password,
        background=background,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/password/change",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(user_limit("auth_password_change"))],
)
async def change_password(
    body: ChangePasswordRequest,
    principal: CurrentUser,
    request: Request,
    background: BackgroundTasks,
    auth: AuthServiceDep,
) -> Response:
    await auth.change_password(
        principal,
        current_password=body.current_password,
        new_password=body.new_password,
        confirm_password=body.confirm_password,
        ip=client_ip_or_none(request.scope),
        background=background,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)

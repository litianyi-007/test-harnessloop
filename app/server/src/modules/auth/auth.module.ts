import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './strategies/jwt.strategy';

@Module({
  imports: [
    PassportModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.getOrThrow<string>('jwt.accessSecret'),
        // `expiresIn` 接受 ms 库的字面量 `StringValue`（如 '15m'）或数字（秒）；
        // 该值来自运行时 env 配置，来源侧无法在编译期收窄为该字面量联合类型，
        // 这里按官方文档惯例做一次受控 cast（不改变运行时行为）。
        signOptions: {
          expiresIn: config.get<string>(
            'jwt.accessExpiresIn',
          ) as unknown as number,
        },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}

<?php
declare(strict_types=1);
namespace LocalLife;

final class ApiException extends \RuntimeException
{
    public function __construct(public readonly int $status, string $message, public readonly string $apiCode = '') { parent::__construct($message); }
}

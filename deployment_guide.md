# QI Energy Deployment Guide

## Правильная последовательность деплоя и настройки

### 1. Деплой токена QI
```solidity
// Deploy QIEnergyToken
QIEnergyToken token = new QIEnergyToken();
```

### 2. Деплой контракта пресейла
```solidity
// Deploy QIPresale with token address
QIPresale presale = new QIPresale(address(token));
```

### 3. Авторизация контракта пресейла в токене
```solidity
// ВАЖНО: Добавить контракт пресейла в authorized список
token.addAuthorized(address(presale));
```

### 4. Минтинг токенов для пресейла
```solidity
// Минтим 20M токенов для пресейла
uint256 presaleAmount = 20_000_000 * 10**18;
token.mint(address(presale), presaleAmount);
```

ИЛИ (если используете улучшенную версию):

### 4. Альтернативный вариант - депозит токенов
```solidity
// Минтим токены на адрес владельца
uint256 presaleAmount = 20_000_000 * 10**18;
token.mint(owner, presaleAmount);

// Даем approve контракту пресейла
token.approve(address(presale), presaleAmount);

// Депозитим токены в контракт
presale.depositTokens(presaleAmount);
```

### 5. Активация пресейла
```solidity
// Активируем пресейл
presale.setPresaleStatus(true);
```

## Проверочный чеклист

- [ ] Токен задеплоен
- [ ] Пресейл задеплоен с правильным адресом токена
- [ ] Пресейл авторизован в токене (addAuthorized)
- [ ] Токены заминчены на контракт пресейла ИЛИ задепозичены
- [ ] Пресейл активирован
- [ ] Проверена возможность покупки малой суммой

## Тестирование

### Проверка покупки:
```javascript
// 1. Проверяем баланс токенов на контракте
let balance = await token.balanceOf(presale.address);
console.log("Presale contract balance:", balance);

// 2. Пробуем купить за ETH
await presale.buyWithETH({ value: ethers.utils.parseEther("0.01") });

// 3. Проверяем получение токенов
let userBalance = await token.balanceOf(userAddress);
console.log("User QI balance:", userBalance);
```

## Важные моменты безопасности

1. **Мультисиг**: Рекомендуется использовать мультисиг кошелек для owner
2. **Аудит**: Проведите аудит перед запуском на mainnet
3. **Тестирование**: Обязательно протестируйте на testnet
4. **Мониторинг**: Настройте мониторинг событий контракта
5. **План экстренной остановки**: Имейте план действий на случай обнаружения проблем